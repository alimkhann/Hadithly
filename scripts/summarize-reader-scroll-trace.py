#!/usr/bin/env python3
"""Validate three reader runs and summarize app hitches within native scroll intervals."""
import argparse
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET


def rows(path):
    root = ET.parse(path).getroot()
    definitions = {node.get('id'): node for node in root.iter() if node.get('id')}
    schema = root.find('.//schema')
    if schema is None:
        raise ValueError(f'Missing trace schema in {path.name}')
    fields = [column.findtext('mnemonic') for column in schema.findall('col')]
    for row in root.findall('.//row'):
        if len(row) != len(fields):
            raise ValueError('Trace row does not match its schema')
        yield {key: definitions[value.get('ref')] if value.get('ref') else value
               for key, value in zip(fields, row)}


def label(node):
    return node.get('fmt') or node.text or ''


def number(node):
    value = float(node.text)
    if not math.isfinite(value):
        raise ValueError('Non-finite trace value')
    return value


def merge(intervals):
    result = []
    for start, end in sorted(intervals):
        if end <= start:
            raise ValueError('Empty or reversed trace interval')
        if result and start <= result[-1][1]:
            result[-1] = (result[-1][0], max(end, result[-1][1]))
        else:
            result.append((start, end))
    return result


def intersection(intervals, masks):
    return merge([(max(start, lower), min(end, upper)) for start, end in intervals
                  for lower, upper in masks if max(start, lower) < min(end, upper)])


def signpost_intervals(path, complete_only=False):
    opened = {}; completed = []
    for row in rows(path):
        name = label(row['name']); process = label(row['process'])
        if name not in ['ReaderMeasuredRun', 'ReaderActiveScroll', 'ReaderAnchorGeometry', 'ScrollProgressPersistence']:
            continue
        subsystem = label(row['subsystem'])
        expected_subsystem = 'com.hadithly.reader.driver' if name == 'ReaderMeasuredRun' else 'com.hadithly.app.reader'
        if subsystem != expected_subsystem or (name != 'ReaderMeasuredRun' and not process.startswith('Hadithly (')):
            continue
        key = (process, name, label(row['identifier']))
        event = label(row['event-type']).lower(); time = number(row['time'])
        if 'begin' in event:
            if key in opened:
                raise ValueError('Duplicate signpost begin')
            opened[key] = time
        elif 'end' in event:
            if key not in opened:
                if complete_only:
                    continue
                raise ValueError('Trace begins inside a required signpost; capture is incomplete')
            completed.append((process, name, opened.pop(key), time))
    if opened and not complete_only:
        raise ValueError('Trace ends inside a required signpost; capture is incomplete')
    return completed


def summarize(signposts, hitches, presentations, activity, updates, gesture_counts, expected_runs=3):
    intervals = signpost_intervals(signposts)
    measured = sorted((start, end) for process, name, start, end in intervals
                      if name == 'ReaderMeasuredRun')
    active = [(start, end) for process, name, start, end in intervals
              if name == 'ReaderActiveScroll' and process.startswith('Hadithly (')]
    if expected_runs not in [1, 3] or len(measured) != expected_runs or any(end - start < 30e9 for start, end in measured):
        raise ValueError(f'Require {expected_runs} complete measured intervals of at least 30 seconds')
    if len({process for process, name, _, _ in intervals if name == 'ReaderMeasuredRun'}) != 1:
        raise ValueError('Require one test driver process')
    if len(gesture_counts) != expected_runs or any(count < 1 for count in gesture_counts):
        raise ValueError('Require the actual gesture count for every measured run')
    app_processes = {process for process, name, _, _ in intervals if name == 'ReaderActiveScroll'}
    if len(app_processes) != 1:
        raise ValueError('Require one continuously running reader process')
    app_process = next(iter(app_processes))
    app_hitches = [(number(row['start']), number(row['start']) + number(row['duration']))
                   for row in rows(hitches) if label(row['process']) == app_process]
    if any(end <= start for start, end in app_hitches):
        raise ValueError('Invalid app hitch interval')
    displayed = sorted({number(row['timestamp']) for row in rows(presentations)})
    app_updates = [number(row['start']) for row in rows(updates) if label(row['process']) == app_process]
    samples = [(number(row['start']) + number(row['duration']), number(row['cpu-total']),
                number(row['memory-physical-footprint'])) for row in rows(activity)
               if label(row['process']) == app_process]
    result = []
    for index, bounds in enumerate(measured):
        scrolling = intersection(active, [bounds])
        if len(scrolling) != gesture_counts[index]:
            raise ValueError('Native scroll intervals do not cover every driven gesture')
        seconds = sum(end - start for start, end in scrolling) / 1e9
        frames = [time for time in displayed if any(start <= time <= end for start, end in scrolling)]
        frame_updates = [time for time in app_updates if any(start <= time <= end for start, end in scrolling)]
        observations = sorted(sample for sample in samples if bounds[0] <= sample[0] <= bounds[1])
        if seconds <= 0 or len(frames) < 2 or len(frame_updates) < 2 or len(observations) < 2:
            raise ValueError('Missing native scroll, app frame-update, presentation or resource evidence')
        for start, end in scrolling:
            if sum(start <= time <= end for time in app_updates) < 2 or sum(start <= time <= end for time in displayed) < 2:
                raise ValueError('Missing frame evidence inside a driven gesture')
        lateness = intersection(app_hitches, scrolling)
        total_ms = sum(end - start for start, end in lateness) / 1e6
        relevant = [(start, end) for start, end in app_hitches if intersection([(start, end)], scrolling)]
        resources = {
            'observed_cpu_seconds': (observations[-1][1] - observations[0][1]) / 1e9,
            'resource_sample_window_seconds': (observations[-1][0] - observations[0][0]) / 1e9,
            'peak_sampled_footprint_mib': max(sample[2] for sample in observations) / 1024**2,
        }
        if resources['observed_cpu_seconds'] < 0 or resources['peak_sampled_footprint_mib'] <= 0:
            raise ValueError('Invalid app resource counters')
        operations = {}
        for name in ['ReaderAnchorGeometry', 'ScrollProgressPersistence']:
            spans = [(start, end) for process, event, start, end in intervals
                     if process == app_process and event == name
                     and start < bounds[1] and end > bounds[0]]
            durations = [(end - start) / 1e6 for start, end in spans]
            operations[name] = {'count': len(spans), 'max_ms': max(durations, default=0),
                                'overlaps_hitch': sum(bool(intersection([span], relevant)) for span in spans)}
        result.append({
            'run': index, 'clock_seconds': (bounds[1] - bounds[0]) / 1e9,
            'active_scroll_seconds': seconds, 'display_presentations': len(frames),
            'app_frame_updates': len(frame_updates),
            'verified_scroll_gestures': len(scrolling),
            'active_hitch_ms_per_second': total_ms / seconds,
            'app_hitch_events': len(relevant), 'active_hitch_union_ms': total_ms,
            'max_app_hitch_ms': max(((end - start) / 1e6 for start, end in relevant), default=0),
            'hitch_intervals_ns': relevant, 'operations': operations, **resources,
        })
    return {
        'runs': result,
        'worst_hitch_ms_per_second': max(run['active_hitch_ms_per_second'] for run in result),
        'note': 'App-attributed hitch intervals intersect native scrolling, with overlaps merged. Presentation counts describe the shared phone display, not app FPS. CPU and footprint are sampled within each run.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['signposts', 'hitches', 'presentations', 'activity', 'updates']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--each-hitch-below', type=float, default=1)
    parser.add_argument('--expected-runs', type=int, choices=[1, 3], default=3)
    parser.add_argument('--gesture-counts', type=int, nargs='+', required=True)
    args = parser.parse_args()
    if not math.isfinite(args.each_hitch_below) or args.each_hitch_below <= 0:
        parser.error('The strict per-run target must be positive and finite')
    result = summarize(args.signposts, args.hitches, args.presentations, args.activity, args.updates, args.gesture_counts, args.expected_runs)
    result['budget_passed'] = result['worst_hitch_ms_per_second'] < args.each_hitch_below
    print(json.dumps(result, indent=2))
    return 0 if result['budget_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
