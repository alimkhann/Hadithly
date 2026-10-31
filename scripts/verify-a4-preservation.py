#!/usr/bin/env python3
"""Prove scoped additions preserve an incoming catalog and project bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--snapshot', type=Path, required=True)
parser.add_argument('--source', action='append', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
sha = lambda data: hashlib.sha256(data).hexdigest()
cat = 'ios/Hadithly/Localizable.xcstrings'
original = (args.snapshot / 'catalog').read_text()
base = json.loads((args.snapshot / 'index-catalog').read_text())['strings']
working = Path(cat).read_text()
indexed = json.loads(subprocess.check_output(['git', 'show', ':' + cat]))['strings']
keys = set()
for source in args.source:
    keys.update(json.loads(Path(source).read_text())['keys'])
added = keys - base.keys()
assert set(indexed) - base.keys() == added
assert all(indexed[key] == value for key, value in base.items()), 'Existing indexed catalog entries changed'
removed = working
decoder = json.JSONDecoder()
for key in added:
    match = re.search(r'^    ' + re.escape(json.dumps(key, ensure_ascii=False)) + r'\s*:\s*', removed, re.M)
    assert match, key
    _, end = decoder.raw_decode(removed, match.end())
    assert removed[end:].startswith(',\n    '), key
    removed = removed[:match.start() + 4] + removed[end + 6:]
assert removed == original, 'Incoming catalog bytes changed'
fingerprints = json.loads((args.snapshot / 'incoming.json').read_text())
projects = {path: digest for path, digest in fingerprints.items() if path != cat}
assert all(sha(Path(path).read_bytes()) == digest for path, digest in projects.items())
baseline = (args.snapshot / 'baseline').read_text().strip()
resources = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', baseline, 'android/app/src/main/res'], text=True).splitlines()
names = {'native_' + sha(key.encode())[:12] for key in keys}
for path in resources:
    if not path.endswith('.xml'): continue
    before = subprocess.check_output(['git', 'show', baseline + ':' + path]).decode()
    after = Path(path).read_text()
    for name in names:
        if re.search(r'<string\b[^>]*name="' + name + r'"', before): continue
        after = re.sub(r'^    <string name="' + name + r'"[^>]*>.*?</string>\n', '', after, flags=re.M)
    assert after == before, path
report = {'baseline': baseline, 'sources': args.source, 'new_catalog_keys': sorted(added),
          'all_existing_indexed_entries_preserved': True, 'exact_incoming_working_catalog_bytes_preserved': True,
          'incoming_catalog_sha256': sha(original.encode()), 'incoming_project_fingerprints': projects,
          'existing_android_resource_bytes_preserved': True,
          'limits': 'Scope proof only. Not native-language, behavior or external-service acceptance.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('Preserved incoming catalog, project files, existing indexed entries and Android resources.')
