#!/usr/bin/env python3
"""Stage scoped new keys or explicitly guarded repairs without unrelated index changes."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, help='Scoped copy JSON containing keys')
parser.add_argument('--stage', action='store_true', help='Write the scoped result to the Git index')
parser.add_argument('--repair-existing', action='store_true', help='Apply only locale repairs with an expected indexed-entry hash in the source JSON')
args = parser.parse_args()
path = 'ios/Hadithly/Localizable.xcstrings'
source_data = json.loads((root / args.source).read_text())
keys = source_data['keys']
working = (root / path).read_text()
indexed = subprocess.check_output(['git', 'show', ':' + path], cwd=root, text=True)
work_entries = json.loads(working)['strings']
base_entries = json.loads(indexed)['strings']
order = list(work_entries)
decoder = json.JSONDecoder()

def match(text, key):
    return re.search(r'^    ' + re.escape(json.dumps(key, ensure_ascii=False)) + r'\s*:\s*', text, re.M)

added, repaired = [], []
for key in sorted(keys, key=order.index, reverse=True):
    if key in base_entries:
        if base_entries[key] != work_entries[key]:
            repair = source_data.get('ios_repairs', {}).get(key, {})
            digest = hashlib.sha256(json.dumps(base_entries[key], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
            if not args.repair_existing or repair.get('expected_index_hash') != digest:
                raise SystemExit(f'Refusing to replace existing indexed key without its expected hash: {key}')
            expected = copy.deepcopy(base_entries[key])
            for locale in repair['locales']:
                expected['localizations'][locale]['stringUnit']['value'] = source_data['locales'][locale][keys.index(key)]
            if expected != work_entries[key]:
                raise SystemExit(f'Refusing unrelated locale or metadata edits in: {key}')
            source = match(working, key)
            _, source_end = decoder.raw_decode(working, source.end())
            destination = match(indexed, key)
            _, destination_end = decoder.raw_decode(indexed, destination.end())
            indexed = indexed[:destination.start()] + working[source.start():source_end] + indexed[destination_end:]
            base_entries[key] = work_entries[key]
            repaired.append(key)
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
if args.stage and (added or repaired):
    blob = subprocess.check_output(['git', 'hash-object', '-w', '--stdin'], cwd=root, input=indexed, text=True).strip()
    subprocess.run(['git', 'update-index', '--cacheinfo', '100644', blob, path], cwd=root, check=True)
print(f'{"Staged" if args.stage else "Would stage"} {len(added)} new catalog keys; repaired {len(repaired)} guarded entries; unrelated indexed entries preserved.')
