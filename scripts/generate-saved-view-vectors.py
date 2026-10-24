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
# Independent semantic encoding shared with native row fingerprints.
def semantic(value):
    if value is None:
        return 'z'
    if isinstance(value, bool):
        return 't' if value else 'f'
    if isinstance(value, str):
        return f's{len(value.encode())}:' + value
    if isinstance(value, (int, float)):
        return 'n' + struct.pack('>d', 0.0 if value == 0 else value).hex()
    if isinstance(value, list):
        return f'a{len(value)}:' + ''.join(map(semantic, value))
    return f'o{len(value)}:' + ''.join(semantic(key) + semantic(value[key]) for key in sorted(value))
source = {
    'items': [{'value': {'hadithId': 'target-Ω', 'createdAt': 1, 'updatedAt': 4500.5,
                         'bookmarkCreatedAt': 1, 'folderId': 'folder', 'folderUpdatedAt': 2},
               'collectionSlug': 'bukhari'}],
    'folders': [{'_id': 'folder', 'name': 'ΟΣ', 'createdAt': 123.5}],
}
rows = [(identity + ':i:' + framed(['target-Ω']), source['items'][0]),
        (identity + ':f:' + framed(['folder']), source['folders'][0])]
digest = framed(['saved-view-manifest-v1'])
for key, value in sorted(rows):
    fingerprint = hashlib.sha256(('saved-view-row-v1:' + semantic(value)).encode()).hexdigest()
    digest = framed([digest, key, fingerprint])
result['manifestSource'] = source
result['manifest'] = {'items': 1, 'folders': 1, 'indexes': 10, 'digest': digest}
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
