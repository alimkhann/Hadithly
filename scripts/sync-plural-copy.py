#!/usr/bin/env python3
"""Synchronize the two scoped count drafts without rewriting unrelated resources."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
source = json.loads((ROOT / 'docs/a4-plural-copy.json').read_text())
path = ROOT / 'ios/Hadithly/Localizable.xcstrings'
working = path.read_text()
entries = json.loads(working)['strings']
indexed = json.loads(subprocess.check_output(['git', 'show', ':ios/Hadithly/Localizable.xcstrings'], cwd=ROOT, text=True))['strings']
outputs = {}
for key in source['keys']:
    repair = source['ios_repairs'][key]
    expected = copy.deepcopy(entries[key])
    for locale in repair['locales']:
        forms = repair['plural_localizations'][locale]
        assert forms.get('other') and all(forms.values()), (key, locale)
        for quantity, text in forms.items():
            implicit = locale == 'ar' and quantity in {'zero', 'two'}
            assert text.count('%lld') == (0 if implicit else 1), (key, locale, quantity)
            assert not re.search(r'%(?!lld)', text), (key, locale, quantity)
        expected['localizations'][locale] = {'variations': {'plural': {
            quantity: {'stringUnit': {'state': 'translated' if locale == 'en' else 'needs_review', 'value': value}}
            for quantity, value in forms.items()
        }}}
        folder = {'en': 'values', 'id': 'values-in', 'es-419': 'values-b+es+419', 'pt-BR': 'values-pt-rBR'}.get(locale, 'values-' + locale)
        resource_path = ROOT / 'android/app/src/main/res' / folder / 'strings.xml'
        resource = outputs.get(resource_path, resource_path.read_text())
        name = source['android_resources'][key]
        block = '<plurals name="' + name + '">\n' + '\n'.join(
            '        <item quantity="' + quantity + '">' + value.replace('%lld', '%d') + '</item>'
            for quantity, value in forms.items()) + '\n    </plurals>'
        resource, changed = re.subn(r'<plurals name="' + re.escape(name) + r'">.*?</plurals>', lambda _: block, resource, flags=re.S)
        assert changed == 1, resource_path
        outputs[resource_path] = resource
    if entries[key] != expected:
        digest = hashlib.sha256(json.dumps(indexed[key], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        assert entries[key] == indexed[key] and digest == repair['expected_index_hash'], f'Unrelated incoming edits in {key}'
        match = re.search(r'^    ' + re.escape(json.dumps(key)) + r'\s*:\s*', working, re.M)
        _, end = json.JSONDecoder().raw_decode(working, match.end())
        block = json.dumps(expected, ensure_ascii=False, indent=2).replace('\n', '\n    ')
        working = working[:match.end()] + block + working[end:]
outputs[path] = working
for path, text in outputs.items():
    if args.check:
        assert path.read_text() == text, f'Plural drafts out of date: {path.relative_to(ROOT)}'
    else:
        path.write_text(text)
print('Two plural drafts x fifteen locales; native review pending.')
