#!/usr/bin/env python3
"""Stage only newly generated catalog keys while preserving every existing index entry."""
import argparse
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, help='Scoped copy JSON containing keys')
parser.add_argument('--stage', action='store_true', help='Write the scoped result to the Git index')
args = parser.parse_args()
path = 'ios/Hadithly/Localizable.xcstrings'
keys = json.loads((root / args.source).read_text())['keys']
working = (root / path).read_text()
indexed = subprocess.check_output(['git', 'show', ':' + path], cwd=root, text=True)
work_entries = json.loads(working)['strings']
base_entries = json.loads(indexed)['strings']
order = list(work_entries)
decoder = json.JSONDecoder()

def match(text, key):
    return re.search(r'^    ' + re.escape(json.dumps(key, ensure_ascii=False)) + r'\s*:\s*', text, re.M)

added = []
for key in sorted(keys, key=order.index, reverse=True):
    if key in base_entries:
        if base_entries[key] != work_entries[key]:
            raise SystemExit(f'Refusing to replace existing indexed key: {key}')
        continue
    anchor = next((item for item in order[order.index(key) + 1:] if item in base_entries), None)
    if anchor is None:
        raise SystemExit(f'No existing following entry for scoped insertion: {key}')
    source = match(working, key)
    _, end = decoder.raw_decode(working, source.end())
    destination = match(indexed, anchor)
    indexed = indexed[:destination.start()] + working[source.start():end] + ',\n' + indexed[destination.start():]
    base_entries[key] = work_entries[key]
    added.append(key)
assert json.loads(indexed)['strings'] == base_entries
if args.stage and added:
    blob = subprocess.check_output(['git', 'hash-object', '-w', '--stdin'], cwd=root, input=indexed, text=True).strip()
    subprocess.run(['git', 'update-index', '--cacheinfo', '100644', blob, path], cwd=root, check=True)
print(f'{"Staged" if args.stage else "Would stage"} {len(added)} new catalog keys; existing indexed entries preserved.')
