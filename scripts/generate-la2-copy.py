#!/usr/bin/env python3
"""Keep the eight native LA2 locales and prepared example in parity."""
import json
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape
ROOT = Path(__file__).resolve().parents[1]
CHECK = "--check" in sys.argv
def output(path, value):
    if CHECK:
        if not path.exists() or path.read_text() != value:
            raise SystemExit(f"Generated LA2 resource is out of date: {path.relative_to(ROOT)}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
source = json.loads((ROOT / "docs/la2-copy.json").read_text())
locales = source["locales"]
assert len(locales) == 8 and source["sample"]["license"] == "CC0-1.0"
catalog_path = ROOT / "ios/Hadithly/Localizable.xcstrings"
text = catalog_path.read_text()
opening = re.search(r'"strings"\s*:\s*\{', text).end()
decoder = json.JSONDecoder()
cursor = opening
while True:
    start = cursor
    cursor += len(text[cursor:]) - len(text[cursor:].lstrip())
    key, end = decoder.raw_decode(text, cursor)
    if not key.startswith("la2."):
        break
    value_start = text.index(":", end) + 1
    value_start += len(text[value_start:]) - len(text[value_start:].lstrip())
    _, cursor = decoder.raw_decode(text, value_start)
    cursor += len(text[cursor:]) - len(text[cursor:].lstrip())
    if text[cursor] == ",": cursor += 1
text = text[:opening] + text[start:]
new_strings = {}
for key, values in source["strings"].items():
    assert len(values) == len(locales) and all(values)
    new_strings["la2." + key] = {"extractionState": "manual", "localizations": {
        locale: {"stringUnit": {"state": "translated", "value": value}} for locale, value in zip(locales, values)}}
block = json.dumps(new_strings, ensure_ascii=False, indent=2)[1:-1].rstrip()
text = text[:opening] + block + "," + text[opening:]
json.loads(text)
output(catalog_path, text)
for index, locale in enumerate(locales):
    path = ROOT / ("android/app/src/main/res/values" + ("" if locale == "en" else "-" + locale)) / "la2.xml"
    entries = "".join(f'    <string name="la2_{key}">{escape(values[index]).replace(chr(39), chr(92)+chr(39))}</string>\n' for key, values in source["strings"].items())
    output(path, '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + entries + "</resources>\n")
samples = dict(zip(locales, source["sample"]["translations"]))
swift = "import Foundation\n\nenum PreparedTranslationExample {\n    static let arabic = " + json.dumps(source["sample"]["arabic"], ensure_ascii=False) + "\n    static let translations: [String: String] = [\n" + "".join(f'        "{locale}": {json.dumps(value, ensure_ascii=False)},\n' for locale, value in samples.items()) + "    ]\n}\n"
output(ROOT / "ios/Hadithly/Features/Onboarding/PreparedTranslationExample.swift", swift)
kotlin = "package com.hadithly.app.features.onboarding\n\nobject PreparedTranslationExample {\n    const val arabic = " + json.dumps(source["sample"]["arabic"], ensure_ascii=False) + "\n    val translations = mapOf(\n" + "".join(f'        "{locale}" to {json.dumps(value, ensure_ascii=False)},\n' for locale, value in samples.items()) + "    )\n}\n"
output(ROOT / "android/app/src/main/kotlin/com/hadithly/app/features/onboarding/PreparedTranslationExample.kt", kotlin)
print(("Validated" if CHECK else "Generated") + " eight locales and the CC0 illustrative sample")
