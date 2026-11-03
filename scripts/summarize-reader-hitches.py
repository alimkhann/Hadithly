#!/usr/bin/env python3
"""Summarize Hadithly hitch intervals from an exported xctrace hitches table."""
import argparse
import json
from pathlib import Path
import statistics
import xml.etree.ElementTree as ET


def summarize(path, duration_seconds):
    root = ET.parse(path).getroot()
    definitions = {element.get('id'): element for element in root.iter() if element.get('id')}

    def resolve(element):
        return definitions[element.get('ref')] if element.get('ref') else element

    intervals = []
    unattributed = 0
    outside_window = 0
    window_end = int(duration_seconds * 1e9)
    for row in root.findall('.//row'):
        process = row.find('process')
        if process is None:
            unattributed += 1
            continue
        if not resolve(process).get('fmt', '').startswith('Hadithly ('):
            continue
        start = int(resolve(row.find('start-time')).text)
        duration = int(resolve(row.find('duration')).text)
        end = min(window_end, start + duration)
        start = max(0, start)
        if end <= start:
            outside_window += 1
            continue
        intervals.append((start, end))
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    durations = sorted((end - start) / 1e6 for start, end in intervals)
    total_ms = sum(end - start for start, end in merged) / 1e6
    return {
        'trace_duration_seconds': duration_seconds,
        'app_hitches': len(intervals),
        'unattributed_hitch_rows': unattributed,
        'app_hitches_outside_window': outside_window,
        'hitch_interval_union_ms': total_ms,
        'hitch_interval_ratio': total_ms / (duration_seconds * 1000),
        'median_hitch_ms': statistics.median(durations) if durations else None,
        'p95_hitch_ms': durations[min(len(durations) - 1, int(len(durations) * .95))] if durations else None,
        'max_hitch_ms': max(durations) if durations else None,
        'interpretation': 'App-attributed hitch intervals, merged to avoid overlap. This is not an average display FPS measurement.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exported_xml', type=Path)
    parser.add_argument('--duration-seconds', type=float, required=True)
    args = parser.parse_args()
    if args.duration_seconds <= 0:
        parser.error('Trace duration must be positive')
    print(json.dumps(summarize(args.exported_xml, args.duration_seconds), indent=2))
