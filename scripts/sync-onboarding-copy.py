#!/usr/bin/env python3
"""Keep Android onboarding copy in the matching iOS catalog locale, without translation."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
catalog = json.loads((ROOT / "ios/Hadithly/Localizable.xcstrings").read_text())["strings"]
failures = []
for locale in LOCALES:
    directory = {"en": "values", "es-419": "values-b+es+419", "pt-BR": "values-pt-rBR"}.get(locale, "values-" + locale)
    path = ROOT / "android/app/src/main/res" / directory / "la2.xml"
    expected = {"la2_" + key[4:]: value["localizations"][locale]["stringUnit"]["value"] for key, value in catalog.items() if key.startswith("la2.")}
    if args.write:
        entries = []
        for key, text in expected.items():
            escaped = escape(text).replace("'", "\\'").replace('"', '\\"')
            entries.append(f'    <string name="{key}">{escaped}</string>')
        path.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <!-- Catalog parity; existing drafts still require native review. -->\n' + "\n".join(entries) + "\n</resources>\n")
    actual = {node.attrib["name"]: (node.text or "").replace("\\'", "'").replace('\\"', '"') for node in ET.parse(path).getroot().findall("string")}
    failures.extend(f"{locale}:{key}" for key, value in expected.items() if actual.get(key) != value)
if failures:
    raise SystemExit("Wrong-locale or stale onboarding copy: " + ", ".join(failures))
print(f"Onboarding catalog parity passes for {len(LOCALES)} locales. Native review remains separate.")
