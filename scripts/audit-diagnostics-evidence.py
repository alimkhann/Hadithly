#!/usr/bin/env python3
"""Check private Sentry exports; write only non-sensitive acceptance evidence."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("exports", type=Path)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
release = json.loads((Path(__file__).resolve().parents[1] / "docs/diagnostics-release.json").read_text())["release"]
evidence = []
for surface in ["ios", "android", "backend", "web"]:
    path = args.exports / f"{surface}-final-event.json"
    event = json.loads(path.read_text())
    tags = dict(event["tags"])
    assert event["release"] == release and tags["surface"] == surface
    assert tags["environment"] == "development"
    assert not event.get("message") and not event.get("request") and not event.get("extra")
    assert not event.get("breadcrumbs") and not event.get("attachments")
    user = event.get("user", {})
    assert set(user) <= {"geo"}
    assert all(value == "[Filtered]" for value in user.get("geo", {}).values())
    assert set(event.get("contexts", {})) <= {"trace"}
    values = event["exception"]["values"]
    assert all(value["value"] in {"synthetic", "native_crash"} for value in values)
    assert all(value["type"] in {"HadithlyNativeFailure", "HadithlyOperationalFailure"} for value in values)
    frames = [frame for value in values for frame in value.get("stacktrace", {}).get("frames", [])]
    frames += [frame for thread in event.get("threads", {}).get("values", []) for frame in thread.get("stacktrace", {}).get("frames", [])]
    for frame in frames:
        assert not any(frame.get(key) for key in ["vars", "pre_context", "post_context", "context_line"])
        assert "/Users/" not in frame.get("abs_path", ""), "Symbol upload contains a local user path"
    assert "LA1SyntheticFailure" not in json.dumps(event)
    readable = [frame for frame in frames if frame.get("in_app") and frame.get("function")]
    if surface in {"ios", "android"}:
        assert readable, "Native app frames are not readable"
    if surface == "android":
        assert any(frame.get("module") == "com.hadithly.app.MainActivity" and
                   frame.get("function", "").startswith("onCreate") and frame.get("lineno") for frame in frames)
    if surface == "ios":
        crash_frames = [frame for frame in frames if frame.get("filename") == "AppEnvironment.swift"
                        and "AppEnvironment.init" in frame.get("function", "") and frame.get("lineno")]
        assert crash_frames, "The synthetic crash site is not symbolicated"
        assert any(image.get("debug_status") == "found" and image.get("features", {}).get("has_symbols")
                   and not image.get("features", {}).get("has_sources")
                   and image.get("image_addr") in {frame.get("image_addr") for frame in crash_frames}
                   for image in event["debug_meta"]["images"])
    # Provider routing keys and account/project metadata stay in the private export.
    evidence.append({"surface": surface, "event_id": event["event_id"], "release": release,
                     "environment": "development", "operation": tags["operation"],
                     "redaction": "passed", "readable_app_frames": len(readable),
                     "private_export_sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
result = {"release": release, "reports": evidence}
if args.output:
    args.output.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"release": release, "surfaces": len(evidence), "redaction": "passed"}))
