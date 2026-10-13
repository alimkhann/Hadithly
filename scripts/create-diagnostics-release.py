#!/usr/bin/env python3
"""Create one content fingerprint for all four LA1 reporting adapters."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ["backend/convex/lib/diagnosticsRelease.ts",
           "ios/Hadithly/Core/Diagnostics/DiagnosticsRelease.swift",
           "android/app/src/main/kotlin/com/hadithly/app/core/diagnostics/DiagnosticsRelease.kt",
           "site/diagnostics-release.js", "docs/diagnostics-release.json"]
digest = hashlib.sha256()
for folder in ["backend/convex", "ios/Hadithly", "android/app/src/main", "site"]:
    for path in sorted((ROOT / folder).rglob("*")):
        name = path.relative_to(ROOT).as_posix()
        if not path.is_file() or name in OUTPUTS or "/_generated/" in name:
            continue
        if path.suffix not in {".ts", ".swift", ".kt", ".xml", ".plist", ".html", ".js", ".css"}:
            continue
        digest.update(name.encode() + b"\0" + path.read_bytes() + b"\0")
release = "hadithly@" + digest.hexdigest()[:12]
contents = [f'export const DIAGNOSTICS_RELEASE = "{release}";\n',
            f'enum DiagnosticsRelease {{ static let value = "{release}" }}\n',
            f'package com.hadithly.app.core.diagnostics\ninternal const val DIAGNOSTICS_RELEASE = "{release}"\n',
            f'window.HADITHLY_DIAGNOSTICS_RELEASE = "{release}";\n',
            json.dumps({"release": release, "source_sha256": digest.hexdigest()}, indent=2) + "\n"]
for output, content in zip(OUTPUTS, contents):
    path = ROOT / output
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
print(release)
