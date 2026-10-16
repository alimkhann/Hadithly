#!/usr/bin/env python3
"""Export scoped native reader screenshots into a reviewable local gallery."""
import argparse
import html
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--xcresult", type=Path, required=True)
parser.add_argument("--android", action="store_true")
parser.add_argument("--output", type=Path, default=ROOT / "docs/verification/reader-status")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="hadithly-reader-captures-") as directory:
    temporary = Path(directory)
    subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(args.xcresult), "--output-path", directory], check=True, capture_output=True)
    for test in json.loads((temporary / "manifest.json").read_text()):
        for attachment in test["attachments"]:
            name = attachment["suggestedHumanReadableName"]
            filename = attachment["exportedFileName"]
            if name.startswith("reader-status-") and filename.endswith(".png"):
                name = name.split("_")[0]
                shutil.copy2(temporary / filename, args.output / f"ios-{name}.png")
if args.android:
    adb = shutil.which("adb") or str(Path.home() / "Library/Android/sdk/platform-tools/adb")
    for name in ["missing", "loading", "failure", "quota", "quota-ar"]:
        subprocess.run([adb, "pull", f"/sdcard/Pictures/reader-status-{name}.png", str(args.output / f"android-reader-status-{name}.png")], check=True, capture_output=True)

cards = []
for path in sorted(args.output.glob("*-reader-status-*.png")):
    title = path.stem.replace("-reader-status-", " · ").replace("-", " ")
    cards.append(f'<figure><a href="{html.escape(path.name)}"><img src="{html.escape(path.name)}" alt="{html.escape(title)}" loading="lazy"></a><figcaption>{html.escape(title)}</figcaption></figure>')
(args.output / "index.html").write_text('''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hadithly · Reader translation states</title>
<style>body{margin:0;background:#eeece7;color:#272720;font:16px system-ui}main{max-width:1320px;margin:auto;padding:32px 24px}h1{font-size:28px;letter-spacing:-.6px}p{max-width:760px;line-height:1.6;color:#58584f}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:24px}figure{margin:0}img{display:block;width:100%;height:auto;border-radius:18px;outline:1px solid #0002}figcaption{padding:12px 2px;font-size:14px}a:focus-visible{outline:3px solid #555;outline-offset:5px}</style>
<main><h1>Reader translation states</h1><p>Actual native captures, October 17, 2026. iOS uses production reader blocks in deterministic fixtures. Android shows the production translation component in a minimal native fixture. Text and allowances are synthetic; these captures do not prove a live generation, purchase, or reset. Open an image to inspect its original resolution.</p><div class="grid">''' + "".join(cards) + "</div></main></html>\n")
print(f"Exported gallery with {len(cards)} captures: {args.output}")
