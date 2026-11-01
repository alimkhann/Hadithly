#!/usr/bin/env python3
"""Measure vertical scrolling in the already-loaded physical iOS reader."""
import argparse
import json
import math
from pathlib import Path
import plistlib
import re
import subprocess

TEST = 'ReaderR6AUITests/testPhysicalLoadedReaderScrollingPerformance'


def run(args):
    target = plistlib.loads(args.xctestrun.read_bytes()).get('HadithlyUITests', {})
    if not (target.get('UseDestinationArtifacts') is True
            and target.get('UITargetAppBundleIdentifier') == 'com.hadithly.app'
            and target.get('EnvironmentVariables', {}).get('HADITHLY_PHYSICAL_SCROLL') == '1'
            and target.get('OnlyTestIdentifiers') == [TEST]
            and not target.get('UITargetAppCommandLineArguments')
            and not target.get('UITargetAppEnvironmentVariables')):
        raise ValueError('Requires the opted-in, destination-only reader metrics configuration')
    args.output.mkdir(parents=True, exist_ok=False)
    log_path = args.output / 'scroll-test.log'
    print('Measuring repeated vertical drags in the installed reader; app reinstall is disabled.', flush=True)
    with log_path.open('w') as log:
        result = subprocess.run([
            'xcodebuild', '-xctestrun', str(args.xctestrun),
            '-destination', f'platform=iOS,id={args.device},arch=arm64e',
            '-parallel-testing-enabled', 'NO', '-collect-test-diagnostics', 'never',
            '-resultBundlePath', str(args.output / 'scroll-test.xcresult'),
            '-only-testing:HadithlyUITests/' + TEST, 'test-without-building',
        ], stdout=log, stderr=subprocess.STDOUT)
    text = log_path.read_text(errors='replace')
    if result.returncode or '** TEST EXECUTE SUCCEEDED **' not in text:
        raise RuntimeError('Physical scrolling test did not pass; inspect the local log')
    metrics = {name: [float(v) for v in values.split(',')] for name, values in
               re.findall(r'measured \[([^]]+)\].*?values: \[([^]]+)\]', text)}
    if not metrics or not all(math.isfinite(v) for values in metrics.values() for v in values):
        raise RuntimeError('Missing or non-finite physical performance measurements')
    (args.output / 'metrics.json').write_text(json.dumps(metrics, indent=2) + '\n')
    if not any('hitch' in name.lower() or 'frame' in name.lower() for name in metrics):
        raise RuntimeError('Scrolling passed, but the device did not emit frame/hitch metrics; no frame result is claimed')
    print('Physical scrolling and frame metrics completed.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--xctestrun', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-physical-scroll', action='store_true', required=True,
                        help='Only use within the session-approved physical-device scope')
    run(parser.parse_args())
