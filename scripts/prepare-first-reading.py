#!/usr/bin/env python3
"""Inspect or prepare existing first-reading references on the development deployment.

This never creates text, changes permission records, or invokes a provider/model.
The internal prepareSlot operation remains the authority for each candidate.
Apply also records the reviewed exact-text incident exclusions for first reading.
"""
import argparse
import hashlib
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEPLOYMENT = "festive-cobra-664"
URL = f"https://{DEPLOYMENT}.eu-west-1.convex.cloud/api/query"
LOCALES = ["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn"]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--apply", action="store_true", help="Record exact-text exclusions and up to three authorized references per available locale. Requires development-change approval.")
parser.add_argument("--report", type=Path, help="Save sanitized readiness counts without text or database IDs.")
args = parser.parse_args()
exclusions = json.loads((ROOT / "docs/product-program/first-reading-exclusions.json").read_text())["entries"]


def convex(*arguments):
    result = subprocess.run(["npx", "convex", "run", "--deployment", DEPLOYMENT, *arguments], cwd=ROOT / "backend", capture_output=True, text=True)
    if result.returncode:
        if "FIRST_READING_NOT_AUTHORIZED" in result.stderr:
            return None
        raise RuntimeError("Development operation failed; inspect the CLI locally without publishing private output.")
    return json.loads(result.stdout)


report = {"deployment": DEPLOYMENT, "applied": args.apply, "verificationDate": datetime.now(timezone.utc).date().isoformat(), "locales": {}, "exactTextExclusionsApplied": 0}
for locale in LOCALES:
    if locale in ("ar", "en"):
        source = "arabic_original" if locale == "ar" else "provider_english"
        expression = f'''const rows = await ctx.db.query("hadiths").withIndex("by_collection", q => q.eq("provider", "sunnah_now").eq("collectionSlug", "bukhari")).take(31); return {{truncated:rows.length>30, candidates:rows.slice(0,30).map(r=>({{hadithId:r._id,canonicalId:r.canonicalId,source:{{kind:{json.dumps(source)}}}}}))}};'''
    else:
        expression = f'''const rows = await ctx.db.query("translations").withIndex("by_language_status_default", q => q.eq("language",{json.dumps(locale)}).eq("status","live").eq("isDefault",true)).take(61); const candidates=[]; for(const r of rows.slice(0,60)) {{ const source=r.evidencePublicationId?{{kind:"published_translation",translationId:r._id}}:r.source==="gemini_ai"&&r.generationKey?{{kind:"ai_translation",translationId:r._id}}:null; if(!source)continue; const h=await ctx.db.get(r.hadithId); if(h)candidates.push({{hadithId:r.hadithId,canonicalId:h.canonicalId,content:r.content,source}}); }} return {{truncated:rows.length>60,candidates}};'''
    inventory = convex("--inline-query", expression)
    for candidate in inventory["candidates"]:
        if "content" in candidate:
            candidate["contentSha256"] = hashlib.sha256(candidate.pop("content").encode()).hexdigest()
    blocked = {(entry["canonicalId"], entry["contentSha256"]): entry for entry in exclusions if entry["locale"] == locale}
    candidates = []
    for candidate in inventory["candidates"]:
        incident = blocked.get((candidate.get("canonicalId"), candidate.get("contentSha256")))
        if incident:
            if args.apply:
                convex("firstReading:blockTranslation", json.dumps({"translationId": candidate["source"]["translationId"], "contentSha256": incident["contentSha256"], "reason": incident["reasonCode"]}))
                report["exactTextExclusionsApplied"] += 1
        else:
            candidates.append(candidate)
    prepared = 0
    rejected = 0
    seen = set()
    if args.apply:
        for candidate in candidates:
            if candidate["hadithId"] in seen:
                continue
            seen.add(candidate["hadithId"])
            result = convex("firstReading:prepareSlot", json.dumps({"locale": locale, "rank": prepared, "hadithId": candidate["hadithId"], "source": candidate["source"]}))
            if result is None:
                rejected += 1
                continue
            prepared += 1
            if prepared == 3:
                break
    public = subprocess.run(["curl", "--fail", "--silent", "--show-error", "--max-time", "30",
        "--header", "Content-Type: application/json", "--data-binary",
        json.dumps({"path": "firstReading:get", "args": {"translationLocale": locale, "timezone": "Asia/Almaty"}, "format": "json"}), URL], capture_output=True, text=True)
    if public.returncode:
        raise RuntimeError("Public HTTPS readback failed")
    envelope = json.loads(public.stdout)
    if envelope.get("status") != "success":
        raise RuntimeError("Public first-reading query failed")
    value = envelope["value"]
    item = {"candidateCount": len(inventory["candidates"]), "scanTruncated": inventory["truncated"], "excluded": len(inventory["candidates"]) - len(candidates), "prepared": prepared, "rejected": rejected, "outcome": value["kind"]}
    if value["kind"] == "ready":
        reading = value["reading"]
        item.update(origin=value["origin"], canonicalId=reading["canonicalId"], exactLanguage=reading["text"]["language"], textKind=reading["text"]["kind"], textCharacters=len(reading["text"]["text"]), isAI=reading["text"]["isAI"])
    report["locales"][locale] = item
    print(f"{locale}: {item['outcome']}; prepared={prepared}; rejected={rejected}", flush=True)
if args.report:
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print("No provider/model calls or permission changes. Readiness is not copy, quality, or release approval.")
