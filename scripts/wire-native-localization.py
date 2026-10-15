#!/usr/bin/env python3
"""Move Kotlin UI literals to resources and inventory the resulting copy.

Run --write once to migrate callers. Subsequent runs preserve existing callers
and resource identities. Translations are supplied by the offline L1 corpus.
"""
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
CODE = ROOT / "android/app/src/main/kotlin/com/hadithly/app"
RESOURCE = ROOT / "android/app/src/main/res/values/native.xml"
HELPER = CODE / "core/preferences/NativeCopy.kt"
PATTERN = re.compile(r'(?:\bText\(\s*(?:text\s*=\s*)?|\bcontentDescription\s*=\s*)("(?:\\.|[^"\\])*\")')
IMPORT = "import com.hadithly.app.core.preferences.nativeText\n"


def parse_template(raw):
    source = raw[1:-1]
    arguments = []
    pieces = []
    cursor = 0
    while cursor < len(source):
        if source[cursor:cursor + 2] == "${":
            depth, end = 1, cursor + 2
            while end < len(source) and depth:
                if source[end] == "{": depth += 1
                elif source[end] == "}": depth -= 1
                end += 1
            if depth: return None
            arguments.append(source[cursor + 2:end - 1])
            pieces.append(f"%{len(arguments)}$s")
            cursor = end
        elif source[cursor] == "$":
            match = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)", source[cursor:])
            if match:
                arguments.append(match.group(1))
                pieces.append(f"%{len(arguments)}$s")
                cursor += len(match.group(0))
            else:
                pieces.append("$"); cursor += 1
        else:
            pieces.append(source[cursor]); cursor += 1
    value = "".join(pieces)
    if arguments:
        value = re.sub(r"%(?![0-9]+\$s)", "%%", value)
    # Decode Kotlin's ordinary escapes, without touching Unicode characters.
    for escaped, actual in [(r"\n", "\n"), (r"\t", "\t"), (r'\"', '"'), (r"\'", "'"), (r"\\", "\\")]:
        value = value.replace(escaped, actual)
    return value, arguments


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    values = {}
    if RESOURCE.exists():
        for node in ET.parse(RESOURCE).getroot().findall("string"):
            decoded = parse_template('"' + (node.text or "") + '"')
            assert decoded is not None
            values[node.attrib["name"]] = decoded[0]
    changed, skipped = 0, []
    for path in sorted((CODE / "features").rglob("*.kt")):
        text = path.read_text()
        edits = []
        for match in PATTERN.finditer(text):
            prefix = text[max(0, match.start() - 120):match.start()]
            line_prefix = text[text.rfind("\n", 0, match.start()) + 1:match.start()]
            if line_prefix.lstrip().startswith(("//", "*")):
                continue
            if ".semantics {" in prefix and "}" not in prefix.split(".semantics {")[-1]:
                skipped.append(f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, match.start()) + 1}")
                continue
            parsed = parse_template(match.group(1))
            if parsed is None:
                skipped.append(f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, match.start()) + 1}")
                continue
            value, arguments = parsed
            if not re.search(r"[A-Za-z]{2}", value) or "http" in value or value in ("Hadithly", "Pro"):
                continue
            key = "native_" + hashlib.sha256(value.encode()).hexdigest()[:12]
            if key in values and values[key] != value:
                raise SystemExit("Resource identity collision")
            values[key] = value
            literal = json.dumps(value, ensure_ascii=False).replace("$", "\\$")
            replacement = f"nativeText({literal}" + "".join(", " + argument for argument in arguments) + ")"
            edits.append((match.start(1), match.end(1), replacement))
        if edits:
            for start, end, replacement in reversed(edits): text = text[:start] + replacement + text[end:]
            if IMPORT not in text:
                package = re.search(r"^package .+\n", text, re.M)
                assert package
                text = text[:package.end()] + "\n" + IMPORT + text[package.end():]
            changed += len(edits)
            if args.write: path.write_text(text)
    if args.write:
        rows = []
        for key, value in sorted(values.items()):
            formatted = "" if re.search(r"%[0-9]+\$s", value) else ' formatted="false"'
            content = escape(value).replace("'", "\\'").replace('"', '\\"').replace("\n", r"\n").replace("\t", r"\t")
            rows.append(f'    <string name="{key}"{formatted}>{content}</string>')
        RESOURCE.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + "\n".join(rows) + "\n</resources>\n")
        cases = "\n".join(f'    {json.dumps(value, ensure_ascii=False).replace(chr(36), chr(92) + chr(36))} -> R.string.{key}' for key, value in sorted(values.items()))
        HELPER.write_text('''package com.hadithly.app.core.preferences

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.core.text.BidiFormatter
import com.hadithly.app.R

@Composable
fun nativeText(source: String, vararg arguments: Any): String =
    LocalContext.current.nativeText(source, *arguments)

fun Context.nativeText(source: String, vararg arguments: Any): String {
    val resource = nativeCopyResource(source) ?: return source
    if (arguments.isEmpty()) return getString(resource)
    val locale = resources.configuration.locales[0]
    val bidi = BidiFormatter.getInstance(locale)
    return getString(resource, *arguments.map { bidi.unicodeWrap(it.toString()) }.toTypedArray())
}

private fun nativeCopyResource(source: String): Int? = when (source) {
''' + cases + '\n    else -> null\n}\n')
    print(f"UI literals moved: {changed}; resources: {len(values)}; manual sites: {len(skipped)}")
    for site in skipped: print(site)


if __name__ == "__main__": main()
