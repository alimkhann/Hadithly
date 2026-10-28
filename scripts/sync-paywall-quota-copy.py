#!/usr/bin/env python3
"""Reuse the existing iOS quota-message drafts in Android; never write the catalog."""
import argparse
import json
from pathlib import Path
import re
from xml.sax.saxutils import escape

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
locales = json.loads((root / 'ios/Hadithly/Localizable.xcstrings').read_text())['strings']['q1.quota_exhausted']['localizations']
folders = {'en': 'values', 'es-419': 'values-b+es+419', 'pt-BR': 'values-pt-rBR', 'id': 'values-in'}
pattern = re.compile(r'(<string name="q1_quota_exhausted">).*?(</string>)')
changed = []
for locale, entry in locales.items():
    path = root / 'android/app/src/main/res' / folders.get(locale, 'values-' + locale) / 'strings.xml'
    text = path.read_text()
    value = escape(entry['stringUnit']['value']).replace("'", r"\'").replace('"', r'\"')
    updated, count = pattern.subn(lambda match: match[1] + value + match[2], text)
    assert count == 1, path
    if text != updated:
        changed.append(locale)
        if not args.check:
            path.write_text(updated)
if args.check and changed:
    raise SystemExit('Quota copy differs: ' + ', '.join(changed))
print(f'Quota copy parity: {len(locales)} locales; changed {len(changed)}; native review pending.')
