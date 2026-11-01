#!/usr/bin/env python3
"""Measure vertical scrolling in the already-loaded physical iOS reader."""
import argparse
import json
import math
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys

TEST = 'ReaderR6AUITests/testPhysicalLoadedReaderScrollingPerformance'


def require_same_workload(actual, expected):
    keys = ['collection', 'volume', 'pageIndex', 'pageKey', 'contentVersion',
            'hadiths', 'textSHA256', 'textBytes', 'automaticGenerationEnabled',
            'lowPowerMode', 'thermalState', 'maximumFramesPerSecond']
    changed = [key for key in keys if key not in actual or actual.get(key) != expected.get(key)]
    def preferences(value):
        return {key: item for key, item in value['preferences'].items() if key != 'updatedAt'}
    if preferences(actual) != preferences(expected):
        changed.append('preferences')
    if actual.get('connectionTransport') != expected.get('connectionTransport'):
        changed.append('connectionTransport')
    if changed:
        raise ValueError('Workload changed: ' + ', '.join(changed))


def run(args):
    target = plistlib.loads(args.xctestrun.read_bytes()).get('HadithlyUITests', {})
    if not (target.get('UseDestinationArtifacts') is True
            and target.get('UITargetAppBundleIdentifier') == 'com.hadithly.app'
            and target.get('EnvironmentVariables', {}).get('HADITHLY_PHYSICAL_SCROLL') == '1'
            and target.get('OnlyTestIdentifiers') == [TEST]
            and not target.get('UITargetAppCommandLineArguments')
            and not target.get('UITargetAppEnvironmentVariables')):
        raise ValueError('Requires the opted-in, destination-only reader metrics configuration')
    environment = target.get('EnvironmentVariables', {})
    if (target.get('UITargetAppPerformanceAntipatternCheckerEnabled') is not False
            or target.get('UITargetAppMainThreadCheckerEnabled') is not False
            or environment.get('DYLD_INSERT_LIBRARIES')
            or any(key.startswith('PERFC_') for key in environment)):
        raise ValueError('Performance captures must disable runtime checkers and injected profilers')
    if args.stack_profile and not args.trace:
        raise ValueError('Stack profiling requires trace mode and is diagnostic only')
    args.output.mkdir(parents=True, exist_ok=False)
    log_path = args.output / 'scroll-test.log'
    print('Measuring repeated vertical drags in the installed reader; app reinstall is disabled.', flush=True)
    trace = None
    trace_log = None
    repetitions = int(environment.get('HADITHLY_SCROLL_REPETITIONS', '3'))
    if repetitions not in [1, 3]:
        raise ValueError('Require one or three repetitions; acceptance still needs three matched runs')
    if args.trace:
        if (target['EnvironmentVariables'].get('HADITHLY_SCROLL_TRACE') != '1'
                or target['EnvironmentVariables'].get('HADITHLY_SCROLL_SECONDS') != '30'):
            raise ValueError('Trace mode requires the 30-second driver without XCTest measurements')
        process_path = args.output / 'device-processes.json'
        details_path = args.output / 'device-details.json'
        subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'details', '--device', args.device,
                        '--json-output', str(details_path)], stdout=subprocess.DEVNULL, check=True)
        transport = json.loads(details_path.read_text())['result']['connectionProperties']['transportType']
        subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'processes', '--device', args.device,
                        '--json-output', str(process_path)], stdout=subprocess.DEVNULL, check=True)
        processes = json.loads(process_path.read_text())['result']['runningProcesses']
        readers = [process['processIdentifier'] for process in processes
                   if process.get('executable', '').endswith('/Hadithly.app/Hadithly')]
        if len(readers) != 1:
            raise ValueError('Require exactly one running native reader process for trace attachment')
        trace_log = (args.output / 'trace.log').open('w')
        notification = f'com.hadithly.reader.trace.ready.{os.getpid()}'
        ready = subprocess.Popen(['/usr/bin/notifyutil', '-1', notification], stdout=subprocess.DEVNULL)
        trace_command = [
            'xcrun', 'xctrace', 'record', '--template', 'Time Profiler' if args.stack_profile else 'Activity Monitor',
            '--instrument', 'Points of Interest',
        ]
        if not args.stack_profile:
            trace_command += ['--instrument', 'Hitches', '--instrument', 'Display',
                '--instrument', 'Core Animation Activity', '--instrument', 'Core Animation Commits',
                '--instrument', 'Core Animation Server', '--instrument', 'Frame Lifetimes']
        trace_command += [
            '--device', args.device,
            '--notify-tracing-started', notification,
            '--time-limit', '20s' if args.stack_profile else '240s',
            '--output', str(args.output / 'scroll.trace'),
        ]
        trace_command += (['--attach', str(readers[0])]
                          if args.stack_profile else ['--all-processes'])
        trace = subprocess.Popen(trace_command, stdout=trace_log, stderr=subprocess.STDOUT)
        try:
            ready.wait(timeout=30)
        except subprocess.TimeoutExpired:
            ready.terminate()
            ready.wait(timeout=10)
            trace.terminate()
            trace.wait(timeout=20)
            trace_log.close()
            raise RuntimeError('Instruments did not report capture readiness; no gestures were started')
    try:
        with log_path.open('w') as log:
            result = subprocess.run([
            'xcodebuild', '-xctestrun', str(args.xctestrun),
            '-destination', f'platform=iOS,id={args.device},arch=arm64e',
            '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
            '-enablePerformanceTestsDiagnostics', 'NO', '-enableCodeCoverage', 'NO',
            '-resultBundlePath', str(args.output / 'scroll-test.xcresult'),
            '-only-testing:HadithlyUITests/' + TEST, 'test-without-building',
            ], stdout=log, stderr=subprocess.STDOUT)
    finally:
        if trace:
            if trace.poll() is None:
                trace.send_signal(signal.SIGINT)
            try:
                trace.wait(timeout=120)
            except subprocess.TimeoutExpired:
                trace.terminate()
                trace.wait(timeout=20)
                raise RuntimeError('Trace finalization exceeded two minutes; capture is not accepted')
            trace_log.close()
    text = log_path.read_text(errors='replace')
    if result.returncode or '** TEST EXECUTE SUCCEEDED **' not in text:
        raise RuntimeError('Physical scrolling test did not pass; inspect the local log')
    if args.trace:
        metadata = re.findall(r'READER_WORKLOAD_METADATA=(\{[^\n]+\})', text)
        movement = re.findall(r'READER_SCROLL_MOVEMENT_POINTS=([\d.]+)', text)
        iterations = re.findall(r'READER_TRACE_ITERATION=(\d+) THERMAL=(\d+)', text)
        counts = [int(value) for value in re.findall(r'READER_TRACE_ITERATION=\d+ THERMAL=\d+ GESTURES=(\d+)', text)]
        if (trace.returncode or not metadata or not movement or float(movement[0]) <= 20
                or [int(value[0]) for value in iterations] != list(range(repetitions))
                or len(counts) != repetitions or min(counts, default=0) < 2):
            raise RuntimeError('Trace, workload identity or requested movement iterations are incomplete')
        if 'disconnected' in (args.output / 'trace.log').read_text(errors='replace').lower():
            raise RuntimeError('Device tracing disconnected; capture is not accepted')
        workload = json.loads(metadata[0])
        workload['connectionTransport'] = transport
        (args.output / 'workload.json').write_text(json.dumps(workload, indent=2) + '\n')
        if args.match_workload:
            require_same_workload(workload, json.loads(args.match_workload.read_text()))
        subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(args.output / 'scroll.trace'),
                        '--toc', '--output', str(args.output / 'trace-toc.xml')], check=True)
        if args.stack_profile:
            subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(args.output / 'scroll.trace'),
                            '--xpath', '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]',
                            '--output', str(args.output / 'profile.xml')], check=True)
            subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(args.output / 'scroll.trace'),
                            '--xpath', '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost" and @category="PointsOfInterest" and not(@dynamic-tracing-enabled-subsystems)]',
                            '--output', str(args.output / 'signposts.xml')], check=True)
            (args.output / 'diagnostic-only.json').write_text(json.dumps({
                'acceptance_capture': False,
                'reason': 'Twenty-second app-only stack sampling; does not cover complete measured runs',
            }, indent=2) + '\n')
            print('App-only stack diagnostic completed; no acceptance result is produced.', flush=True)
            return 0
        schemas = {
            'signposts': 'os-signpost', 'hitches': 'hitches',
            'presentations': 'display-surface-swap', 'activity': 'activity-monitor-process-live',
            'updates': 'hitches-updates',
        }
        command = [sys.executable, str(Path(__file__).with_name('summarize-reader-scroll-trace.py')),
                   '--expected-runs', str(repetitions), '--gesture-counts', *map(str, counts)]
        with (args.output / 'exports.log').open('w') as log:
            for key, schema in schemas.items():
                selector = f'@schema="{schema}"'
                if key == 'signposts':
                    selector += ' and @category="PointsOfInterest" and not(@dynamic-tracing-enabled-subsystems)'
                destination = args.output / (key + '.xml')
                subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(args.output / 'scroll.trace'),
                                '--xpath', f'/trace-toc/run[@number="1"]/data/table[{selector}]',
                                '--output', str(destination)], stdout=log, stderr=subprocess.STDOUT, check=True)
                command += ['--' + key, str(destination)]
        summary = subprocess.run(command, capture_output=True, text=True)
        (args.output / 'native-summary.json').write_text(summary.stdout)
        if summary.stderr:
            (args.output / 'summary-error.log').write_text(summary.stderr)
        if summary.returncode not in [0, 1] or not summary.stdout:
            raise RuntimeError('Native frame/hitch validation failed; inspect summary-error.log')
        report = json.loads(summary.stdout)
        print(f'Native capture validated. Strict per-run target passed: {report["budget_passed"]}', flush=True)
        return summary.returncode
    metrics = {name: [float(v) for v in values.split(',')] for name, values in
               re.findall(r'measured \[([^]]+)\].*?values: \[([^]]+)\]', text)}
    if not metrics or not all(math.isfinite(v) for values in metrics.values() for v in values):
        raise RuntimeError('Missing or non-finite physical performance measurements')
    (args.output / 'metrics.json').write_text(json.dumps(metrics, indent=2) + '\n')
    if target.get('EnvironmentVariables', {}).get('HADITHLY_SCROLL_SECONDS'):
        durations = metrics.get('Clock Monotonic Time, s', [])
        if not durations:
            durations = next((values for name, values in metrics.items() if 'Clock' in name and name.endswith(', s')), [])
        metadata = re.findall(r'READER_WORKLOAD_METADATA=(\{[^\n]+\})', text)
        movement = re.findall(r'READER_SCROLL_MOVEMENT_POINTS=([\d.]+)', text)
        if (len(durations) < 3 or min(durations) < 30 or not metadata
                or not movement or min(float(value) for value in movement) <= 20):
            raise RuntimeError('Long-form scrolling needs three 30-second runs, pinned metadata and proven movement')
        frames = metrics.get('Frame Count (ReaderActiveScroll), frames', [])
        active = metrics.get('Duration (ReaderActiveScroll), s', [])
        if (len(frames) != len(durations) or len(active) != len(durations)
                or min(frames, default=0) <= 0 or min(active, default=0) <= 0):
            raise RuntimeError('Native scroll intervals did not emit valid frame/active-duration metrics; no acceptance result')
        (args.output / 'workload.json').write_text(json.dumps(json.loads(metadata[0]), indent=2) + '\n')
        if args.match_workload:
            expected = json.loads(args.match_workload.read_text())
            actual = json.loads(metadata[0])
            require_same_workload(actual, expected)
    if not any('hitch' in name.lower() or 'frame' in name.lower() for name in metrics):
        raise RuntimeError('Scrolling passed, but the device did not emit frame/hitch metrics; no frame result is claimed')
    print('Physical scrolling and frame metrics completed.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--xctestrun', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--match-workload', type=Path,
                        help='Reject a comparison with different content or display settings')
    parser.add_argument('--trace', action='store_true',
                        help='Use Instruments frame capture and a gesture-only XCTest driver')
    parser.add_argument('--stack-profile', action='store_true',
                        help='Capture a short app-only CPU stack diagnostic, never an acceptance result')
    parser.add_argument('--allow-physical-scroll', action='store_true', required=True,
                        help='Only use within the session-approved physical-device scope')
    raise SystemExit(run(parser.parse_args()))
