#!/usr/bin/env python3
"""Generate and audit the Wave 1 native localization resources.

The script is deliberately deterministic. It never replaces an existing
translation. Missing values are copied from the English source and marked as
drafts in the String Catalog or in the Android XML comment. Native review is
still required before release.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS_CATALOG = ROOT / "ios/Hadithly/Localizable.xcstrings"
ANDROID_RES = ROOT / "android/app/src/main/res"
ANDROID_RESOURCE_FILES = ("strings.xml", "la2.xml")
LEDGER = ROOT / "docs/LOCALIZATION_WAVE1_REVIEW_LEDGER.tsv"
DRAFTS_JSON = ROOT / "docs/localization/WAVE1_DRAFTS.json"

WAVE1 = (
    "en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur",
    "fr", "es-419", "pt-BR", "sw", "hi", "bn",
)

ANDROID_QUALIFIERS = {
    "en": "values",
    "es-419": "values-b+es+419",
    "pt-BR": "values-pt-rBR",
}

PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:@|lld|d|f|s)")
SWIFT_LITERAL_RE = re.compile(
    r"(?:Text|Label|Button|navigationTitle|accessibilityLabel|alert)\(\"([^\"]+)\""
)
KOTLIN_LITERAL_RE = re.compile(
    r"(?:Text|title|subtitle|label|contentDescription|text)\s*[=(]\s*\"([^\"]+)\""
)


def android_qualifier(locale: str) -> str:
    if locale in ANDROID_QUALIFIERS:
        return ANDROID_QUALIFIERS[locale]
    return f"values-{locale}"


def xml_escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "\\\"")
        .replace("'", "\\'")
    )


def string_value(entry: dict) -> str | None:
    unit = entry.get("stringUnit")
    return unit.get("value") if isinstance(unit, dict) else None


def catalog_source_value(entry: dict, key: str) -> dict:
    """Return an English entry, including its plural shape."""
    localizations = entry.setdefault("localizations", {})
    english = localizations.get("en")
    if english is not None:
        return english
    return {
        "stringUnit": {
            "state": "needs_review",
            "value": key,
        }
    }


def catalog_texts(entry: dict) -> list[str]:
    texts: list[str] = []
    if value := string_value(entry):
        texts.append(value)
    for variation in entry.get("variations", {}).get("plural", {}).values():
        if value := string_value(variation):
            texts.append(value)
    return texts


def clone_as_draft(source: dict) -> dict:
    draft = copy.deepcopy(source)
    if "stringUnit" in draft:
        draft["stringUnit"]["state"] = "needs_review"
    for variation in draft.get("variations", {}).get("plural", {}).values():
        if "stringUnit" in variation:
            variation["stringUnit"]["state"] = "needs_review"
    return draft


def write_ios_drafts() -> tuple[int, int]:
    catalog = json.loads(IOS_CATALOG.read_text())
    generated = 0
    keys = 0
    for key, entry in catalog["strings"].items():
        keys += 1
        source = catalog_source_value(entry, key)
        localizations = entry.setdefault("localizations", {})
        for locale in WAVE1:
            if locale not in localizations:
                localizations[locale] = clone_as_draft(source)
                generated += 1
    IOS_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    return keys, generated


def reset_generated_ios_drafts() -> int:
    """Restore generated values to their English source without touching translations."""
    catalog = json.loads(IOS_CATALOG.read_text())
    reset = 0
    for key, entry in catalog["strings"].items():
        source = catalog_source_value(entry, key)
        source_plural = source.get("variations", {}).get("plural", {})
        for locale, localization in entry.get("localizations", {}).items():
            if locale == "en":
                continue
            units = []
            if "stringUnit" in localization:
                units.append((localization["stringUnit"], source.get("stringUnit")))
            for quantity, unit in localization.get("variations", {}).get("plural", {}).items():
                units.append((unit, source_plural.get(quantity) or source_plural.get("other")))
            for unit, source_unit in units:
                if unit.get("state") != "needs_review" or source_unit is None:
                    continue
                unit["value"] = source_unit.get("value", key)
                reset += 1
    IOS_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    return reset


def apply_offline_drafts() -> int:
    """Apply only the committed, offline GPT-authored draft corpus."""
    drafts = json.loads(DRAFTS_JSON.read_text())
    applied = 0
    catalog = json.loads(IOS_CATALOG.read_text())
    for locale, values in drafts.get("ios", {}).items():
        for key, value in values.items():
            entry = catalog["strings"].get(key)
            if entry is None:
                continue
            target = entry.setdefault("localizations", {}).get(locale)
            if target is None or "stringUnit" not in target:
                continue
            if target["stringUnit"].get("state") == "needs_review":
                target["stringUnit"]["value"] = value
                applied += 1
    IOS_CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")

    android_drafts = drafts.get("android", {})
    if not android_drafts:
        android_drafts = {
            locale: {key.replace(".", "_"): value for key, value in values.items()}
            for locale, values in drafts.get("ios", {}).items()
        }
    for locale, values in android_drafts.items():
        for filename in ANDROID_RESOURCE_FILES:
            path = ANDROID_RES / android_qualifier(locale) / filename
            if not path.exists():
                continue
            root = ET.parse(path).getroot()
            changed = False
            for node in root.findall("string"):
                if node.attrib.get("name") in values:
                    node.text = values[node.attrib["name"]]
                    changed = True
            if changed:
                ET.indent(root, space="    ")
                ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
                applied += sum(node.attrib.get("name") in values for node in root.findall("string"))
    return applied


def android_nodes(path: Path) -> tuple[dict[str, ET.Element], dict[str, ET.Element]]:
    root = ET.parse(path).getroot()
    strings = {node.attrib["name"]: node for node in root.findall("string")}
    plurals = {node.attrib["name"]: node for node in root.findall("plurals")}
    return strings, plurals


def write_android_drafts() -> tuple[int, int]:
    total = 0
    generated = 0
    for filename in ANDROID_RESOURCE_FILES:
        base_path = ANDROID_RES / "values" / filename
        base_strings, base_plurals = android_nodes(base_path)
        total += len(base_strings) + len(base_plurals)
        for locale in WAVE1:
            if locale == "en":
                continue
            path = ANDROID_RES / android_qualifier(locale) / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            if path.exists():
                root = ET.parse(path).getroot()
            else:
                root = ET.Element("resources")
                root.append(ET.Comment("Generated English drafts remain pending native-speaker review."))
            existing_strings, existing_plurals = android_nodes(path) if path.exists() else ({}, {})
            for name, source in base_strings.items():
                if name in existing_strings:
                    continue
                node = ET.Element("string", {"name": name})
                node.text = source.text
                root.append(node)
                generated += 1
            for name, source in base_plurals.items():
                if name in existing_plurals:
                    continue
                node = ET.Element("plurals", {"name": name})
                for item in source.findall("item"):
                    child = ET.SubElement(node, "item", {"quantity": item.attrib["quantity"]})
                    child.text = item.text
                root.append(node)
                generated += 1
            ET.indent(root, space="    ")
            ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
    return total, generated


def placeholders(text: str) -> tuple[str, ...]:
    return tuple(sorted(PLACEHOLDER_RE.findall(text)))


def audit_ios(allow_drafts: bool) -> tuple[int, int, list[str], Counter[str]]:
    catalog = json.loads(IOS_CATALOG.read_text())
    missing: list[str] = []
    generated = 0
    category_counts: Counter[str] = Counter()
    for key, entry in catalog["strings"].items():
        source = catalog_source_value(entry, key)
        source_placeholder_set = set(token for text in catalog_texts(source) for token in placeholders(text))
        for locale in WAVE1:
            localization = entry.get("localizations", {}).get(locale)
            if localization is None:
                missing.append(f"ios:{locale}:{key}")
                continue
            if any(
                token not in source_placeholder_set
                for text in catalog_texts(localization)
                for token in placeholders(text)
            ):
                missing.append(f"ios-placeholder:{locale}:{key}")
            if not allow_drafts:
                source_texts = catalog_texts(source)
                target_texts = catalog_texts(localization)
                if any(
                    unit.get("state") == "needs_review" and unit.get("value") in source_texts
                    for unit in [localization.get("stringUnit", {})]
                    + list(localization.get("variations", {}).get("plural", {}).values())
                    if isinstance(unit, dict)
                ):
                    missing.append(f"ios-untranslated-draft:{locale}:{key}")
            if any(
                unit.get("state") == "needs_review"
                for unit in [localization.get("stringUnit", {})]
                + list(localization.get("variations", {}).get("plural", {}).values())
                if isinstance(unit, dict)
            ):
                generated += 1
        category_counts[category_for(key)] += 1
    return len(catalog["strings"]), generated, missing, category_counts


def audit_android(allow_drafts: bool) -> tuple[int, int, list[str], Counter[str]]:
    missing: list[str] = []
    generated = 0
    category_counts: Counter[str] = Counter()
    total = 0
    for filename in ANDROID_RESOURCE_FILES:
        base_strings, base_plurals = android_nodes(ANDROID_RES / "values" / filename)
        total += len(base_strings) + len(base_plurals)
        for locale in WAVE1[1:]:
            path = ANDROID_RES / android_qualifier(locale) / filename
            if not path.exists():
                missing.append(f"android:{locale}:{filename}")
                continue
            strings, plurals = android_nodes(path)
            for name, source in base_strings.items():
                target = strings.get(name)
                if target is None or not (target.text or "").strip():
                    missing.append(f"android:{locale}:{name}")
                elif (target.text or "") == (source.text or ""):
                    generated += 1
                    if not allow_drafts and name != "app_name":
                        missing.append(f"android-untranslated-draft:{locale}:{name}")
                elif placeholders(target.text or "") != placeholders(source.text or ""):
                    missing.append(f"android-placeholder:{locale}:{name}")
                category_counts[category_for(name)] += 1
            for name, source in base_plurals.items():
                target = plurals.get(name)
                if target is None:
                    missing.append(f"android:{locale}:{name}")
                    continue
                source_quantities = {item.attrib["quantity"] for item in source.findall("item")}
                target_items = {item.attrib["quantity"]: item for item in target.findall("item")}
                for quantity in source_quantities:
                    item = target_items.get(quantity)
                    source_item = source.find(f"item[@quantity='{quantity}']")
                    if item is None:
                        missing.append(f"android-plural:{locale}:{name}:{quantity}")
                    elif (item.text or "") == (source_item.text or ""):
                        generated += 1
                        if not allow_drafts:
                            missing.append(f"android-untranslated-draft:{locale}:{name}:{quantity}")
                category_counts[category_for(name)] += 1
    return total, generated, missing, category_counts


def category_for(key: str) -> str:
    value = key.lower()
    if any(token in value for token in ("e3", "e4", "evidence", "report", "source", "consent")):
        return "evidence"
    if any(token in value for token in ("q1", "q2", "quota", "allowance", "ai", "translation")):
        return "ai-quota"
    if any(token in value for token in ("purchase", "subscribe", "renew", "pro", "billing", "restore", "annual", "monthly")):
        return "purchase"
    if any(token in value for token in ("privacy", "usage", "crash", "sentry", "offline")):
        return "privacy"
    if any(token in value for token in ("export", "portable", "json")):
        return "export"
    if any(token in value for token in ("delete", "remove", "clear", "withdraw")):
        return "deletion"
    if any(token in value for token in ("authentic", "grade", "sunnah", "hadith source")):
        return "authenticity"
    return "reading"


def source_keys() -> set[str]:
    catalog = json.loads(IOS_CATALOG.read_text())
    return set(catalog["strings"])


def find_hardcoded() -> tuple[list[str], list[str]]:
    swift: list[str] = []
    for path in (ROOT / "ios/Hadithly").rglob("*.swift"):
        if path.name.endswith("Tests.swift"):
            continue
        for match in SWIFT_LITERAL_RE.finditer(path.read_text(errors="ignore")):
            value = match.group(1).strip()
            if value and not value.startswith("http") and len(value) > 1:
                swift.append(f"{path.relative_to(ROOT)}:{value}")
    kotlin: list[str] = []
    for path in (ROOT / "android/app/src/main/kotlin").rglob("*.kt"):
        for match in KOTLIN_LITERAL_RE.finditer(path.read_text(errors="ignore")):
            value = match.group(1).strip()
            if value and not value.startswith("http") and len(value) > 1:
                kotlin.append(f"{path.relative_to(ROOT)}:{value}")
    return sorted(set(swift)), sorted(set(kotlin))


def write_ledger() -> None:
    ios_catalog = json.loads(IOS_CATALOG.read_text())["strings"]
    android_strings, android_plurals = android_nodes(ANDROID_RES / "values/strings.xml")
    rows = ["platform\tlocale\tcategory\tkeys\tgenerated_drafts\tnative_reviewer\tstatus"]
    for platform, locale_map in (("ios", ios_catalog), ("android", {**android_strings, **android_plurals})):
        for locale in WAVE1:
            for category in ("reading", "authenticity", "ai-quota", "purchase", "privacy", "evidence", "export", "deletion"):
                keys = [key for key in locale_map if category_for(key) == category]
                generated = 0
                if platform == "ios":
                    for key in keys:
                        loc = locale_map[key].get("localizations", {}).get(locale, {})
                        units = [loc.get("stringUnit", {})] + list(loc.get("variations", {}).get("plural", {}).values())
                        generated += sum(unit.get("state") == "needs_review" for unit in units if isinstance(unit, dict))
                elif locale != "en":
                    path = ANDROID_RES / android_qualifier(locale) / "strings.xml"
                    if path.exists():
                        strings, plurals = android_nodes(path)
                        for key in keys:
                            target = strings.get(key)
                            if target is None:
                                target = plurals.get(key)
                            source = android_strings.get(key)
                            if source is None:
                                source = android_plurals.get(key)
                            if target is not None and source is not None and ET.tostring(target, encoding="unicode") == ET.tostring(source, encoding="unicode"):
                                generated += 1
                rows.append("\t".join((platform, locale, category, str(len(keys)), str(generated), "native speaker", "draft" if generated else "review required")))
    LEDGER.write_text("\n".join(rows) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="add missing locale drafts")
    parser.add_argument("--reset-drafts", action="store_true", help="restore generated iOS drafts to their English source")
    parser.add_argument("--apply-drafts", action="store_true", help="apply the committed offline draft corpus")
    parser.add_argument("--ledger", action="store_true", help="write the review ledger")
    parser.add_argument("--allow-drafts", action="store_true", help="check resource structure while allowing untranslated drafts")
    parser.add_argument("--strict", action="store_true", help="fail on hardcoded native UI literals")
    args = parser.parse_args()

    if args.write:
        ios_keys, ios_generated = write_ios_drafts()
        android_keys, android_generated = write_android_drafts()
        print(f"generated iOS draft entries: {ios_generated} across {ios_keys} keys")
        print(f"generated Android draft resources: {android_generated} across {android_keys} resources")
    if args.reset_drafts:
        print(f"reset iOS generated draft units: {reset_generated_ios_drafts()}")
    if args.apply_drafts:
        print(f"applied offline draft values: {apply_offline_drafts()}")
    if args.ledger:
        write_ledger()
        print(f"wrote {LEDGER.relative_to(ROOT)}")

    ios_keys, ios_drafts, ios_missing, ios_categories = audit_ios(args.allow_drafts)
    android_keys, android_drafts, android_missing, android_categories = audit_android(args.allow_drafts)
    swift, kotlin = find_hardcoded()
    print(f"iOS: {ios_keys} keys, {ios_drafts} draft units, {len(ios_missing)} failures")
    print(f"Android: {android_keys} resources, {android_drafts} English-copy drafts, {len(android_missing)} failures")
    print(f"hardcoded candidates: Swift {len(swift)}, Kotlin {len(kotlin)}")
    if swift:
        print("Swift candidates:")
        print("\n".join(f"  {item}" for item in swift[:20]))
    if kotlin:
        print("Kotlin candidates:")
        print("\n".join(f"  {item}" for item in kotlin[:20]))
    failures = ios_missing + android_missing
    if args.strict:
        failures += [f"hardcoded:{item}" for item in swift + kotlin]
    if failures:
        print("failures:", file=sys.stderr)
        print("\n".join(failures[:80]), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
