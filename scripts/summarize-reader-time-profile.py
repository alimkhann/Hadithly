#!/usr/bin/env python3
"""Summarize an exported xctrace time-profile table without retaining user data."""
import argparse
from collections import Counter
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def summarize(path):
    root = ET.parse(path).getroot()
    definitions = {element.get('id'): element for element in root.iter() if element.get('id')}

    def resolve(element):
        return definitions[element.get('ref')] if element.get('ref') else element

    totals = Counter()
    stacks = Counter()
    weights = Counter()
    for row in root.findall('.//row'):
        totals['input_samples'] += 1
        if not resolve(row.find('process')).get('fmt', '').startswith('Hadithly ('):
            continue
        totals['all_samples'] += 1
        thread = resolve(row.find('thread'))
        if not thread.get('fmt', '').startswith('Main Thread'):
            continue
        totals['main_thread_samples'] += 1
        weight = int(resolve(row.find('weight')).text)
        weights['main_thread_sampled_nanoseconds'] += weight
        raw_backtrace = row.find('tagged-backtrace')
        if raw_backtrace is None:
            totals['main_samples_without_backtrace'] += 1
            continue
        backtrace = resolve(raw_backtrace)
        names = set()
        for unresolved in backtrace.findall('frame'):
            frame = resolve(unresolved)
            binary = frame.find('binary')
            if binary is not None and resolve(binary).get('name', '').startswith('Hadithly'):
                names.add(frame.get('name', '<unknown>'))
        stacks.update(names)
    if not totals['main_thread_samples']:
        raise ValueError('No main-thread samples in this time-profile export')
    return {
        **totals, **weights,
        'inclusive_app_stacks': dict(stacks.most_common(35)),
        'interpretation': 'Inclusive stacks overlap. Statistical CPU samples do not measure display FPS.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('exported_xml', type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize(args.exported_xml), indent=2))
