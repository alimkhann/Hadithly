#!/usr/bin/env python3
"""Regenerate native view fixtures from actual folder policy and portable key encoding."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
inputs = ['  Folder  ', 'ΟΣ', 'οσ', 'ος', '\ufeffÉ\u00a0', 'E\u0301', 'İ', 'K', 'ΣΟΣ']
code = 'import { normalizedFolderName } from "./backend/convex/lib/savedFolderPolicy.ts"; const inputs=' + json.dumps(inputs) + '; console.log(JSON.stringify(inputs.map(input=>({input,expected:normalizedFolderName(input).normalizedName}))));'
names = json.loads(subprocess.check_output(['node', '--no-warnings', '--input-type=module', '-e', code], cwd=root, text=True))
def framed(values):
    return hashlib.sha256(''.join(f'{len(v.encode())}:{v}' for v in values).encode()).hexdigest()
scope = framed(['fixture', 'subject-a']) + ':' + framed(['fixture|owner-a', 'subject-a'])
identity = scope + ':' + framed(['epoch', 'generation']) + ':view'
rank = f'{(~struct.unpack(">Q", struct.pack(">d", 4500.5))[0]) & ((1<<64)-1):016x}:' + 'target-Ω'.encode().hex()
result = {'names': names, 'identity': identity, 'rank': rank,
          'prefix': identity + ':q:' + framed(['Bookmarks', 'folder', 'folder', 'collection', 'bukhari']) + ':'}
content = json.dumps(result, ensure_ascii=True, indent=2) + '\n'
for relative in ['ios/HadithlyTests/Fixtures/SavedViewVectors.json', 'android/app/src/androidTest/assets/saved-view-vectors.json']:
    path = root / relative
    if args.check:
        if not path.exists() or path.read_text() != content:
            raise SystemExit(f'Stale Saved view fixture: {relative}')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
print('Saved view naming and portable key fixtures verified' if args.check else 'Saved view fixtures generated')
