#!/usr/bin/env python3
"""Summarize sampled main-thread work during complete native reader scroll intervals."""
import argparse
from collections import Counter
import json
from pathlib import Path
import runpy
import xml.etree.ElementTree as ET

TRACE = runpy.run_path(str(Path(__file__).with_name('summarize-reader-scroll-trace.py')))


def summarize(profile, signposts):
    intervals = TRACE['signpost_intervals'](signposts, complete_only=True)
    active = [(start, end) for process, name, start, end in intervals if name == 'ReaderActiveScroll']
    root = ET.parse(profile).getroot()
    definitions = {node.get('id'): node for node in root.iter() if node.get('id')}
    leaf = Counter(); functions = Counter(); groups = Counter(); total = 0
    for row in TRACE['rows'](profile):
        time = TRACE['number'](row['time'])
        if (not TRACE['label'](row['process']).startswith('Hadithly (')
                or not TRACE['label'](row['thread']).startswith('Main Thread')
                or TRACE['label'](row['thread-state']) != 'Running'
                or not any(start <= time <= end for start, end in active)):
            continue
        weight = TRACE['number'](row['weight']) / 1e6
        if weight <= 0:
            raise ValueError('Invalid CPU sample weight')
        total += weight
        names = []; modules = []; app_functions = set()
        for frame in row['stack'].findall('frame'):
            frame = definitions[frame.get('ref')] if frame.get('ref') else frame
            name = frame.get('name', '')
            names.append(name)
            binary = frame.find('binary')
            if binary is not None:
                binary = definitions[binary.get('ref')] if binary.get('ref') else binary
                module = binary.get('name', '')
                modules.append(module)
                if module == 'Hadithly' and name not in ['main', '<deduplicated_symbol>'] and not name.startswith('0x'):
                    app_functions.add(name)
        if not modules:
            raise ValueError('Missing CPU backtrace binary information')
        leaf[modules[0]] += weight
        for name in app_functions:
            functions[name] += weight
        matches = {
            'library_sync': any('LibrarySync.' in name for name in names),
            'reader_progress_save': any('ReaderModel.flushScrollProgress' in name for name in names),
            'guest_data_store': any('GuestDataStore.' in name for name in names),
            'json_coder': any('JSONEncoder' in name or 'JSONDecoder' in name for name in names),
            'core_text': 'CoreText' in modules,
            'accessibility': any('Accessibility' in name or 'accessibility' in name for name in names),
        }
        for name, matched in matches.items():
            if matched:
                groups[name] += weight
    if not active or total <= 0:
        raise ValueError('No sampled main-thread work inside complete native scrolling intervals')
    def percentages(counter):
        return {name: round(value / total * 100, 4) for name, value in counter.most_common()}
    return {
        'acceptance_capture': False,
        'complete_native_scroll_intervals': len(active),
        'main_thread_sampled_ms': total,
        'leaf_module_percent': percentages(leaf),
        'inclusive_stack_group_percent': percentages(groups),
        'app_function_inclusive_percent': dict(list(percentages(functions).items())[:25]),
        'note': 'Short diagnostic only. Leaf module shares partition sampled CPU work. Inclusive groups and functions overlap and must not be added. Sampling does not measure blocked time or establish hitch causation.',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--signposts', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(summarize(args.profile, args.signposts), indent=2))
