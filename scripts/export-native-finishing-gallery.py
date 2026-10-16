#!/usr/bin/env python3
"""Export the finishing tests' original PNGs and build a local review gallery."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "docs/verification/native-finishing"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ios-result", type=Path)
parser.add_argument("--android", action="store_true")
parser.add_argument("--output", type=Path, default=DEFAULT_OUT)
parser.add_argument("--android-since", type=int, help="Only screenshots modified since this Unix timestamp")
parser.add_argument("--adb", default=str(Path.home() / "Library/Android/sdk/platform-tools/adb"))
args = parser.parse_args()
OUT = args.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)

if args.ios_result:
    with tempfile.TemporaryDirectory(prefix="hadithly-finishing-export-") as directory:
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(args.ios_result), "--output-path", directory], check=True, stdout=subprocess.DEVNULL)
        for test in json.loads((Path(directory) / "manifest.json").read_text()):
            if not test["testIdentifier"].startswith(("NativeFinishingUITests/", "ReaderSettingsUITests/")):
                continue
            for attachment in test["attachments"]:
                name = attachment["suggestedHumanReadableName"].split("_0_")[0]
                if test["testIdentifier"].startswith("ReaderSettingsUITests/") and name.startswith(("appearance-", "reader-")):
                    name = "finishing-settings-" + name
                if name.startswith("finishing-") and attachment["exportedFileName"].endswith(".png") and not attachment["isAssociatedWithFailure"]:
                    target = OUT / "ios" / (name + ".png")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(Path(directory) / attachment["exportedFileName"], target)
if args.android:
    names = subprocess.check_output([args.adb, "shell", "ls", "/sdcard/Pictures"], text=True).splitlines()
    for name in names:
        if re.fullmatch(r"finishing-[a-z0-9_-]+\.png", name):
            if args.android_since:
                modified = int(subprocess.check_output([args.adb, "shell", "stat", "-c", "%Y", "/sdcard/Pictures/" + name], text=True).strip())
                if modified < args.android_since:
                    continue
            target = OUT / "android" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run([args.adb, "pull", "/sdcard/Pictures/" + name, str(target)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

items = []
for platform in ("ios", "android"):
    for path in sorted((OUT / platform).glob("finishing-*.png")):
        raw = path.read_bytes()
        assert raw[:8] == b"\x89PNG\r\n\x1a\n", path
        width, height = struct.unpack(">II", raw[16:24])
        name = path.stem.removeprefix("finishing-")
        section = "Normal RTL" if name.startswith("normal-") else "Accessibility" if "large" in name else "Settings" if "settings-" in name else "Reader" if "reader" in name else "Navigation" if "navigation" in name else "Paywall" if "paywall" in name else "Auth" if any(word in name for word in ("auth-", "password", "recovery", "sign-up", "email-code")) else "Onboarding"
        items.append({"platform": platform, "file": str(path.relative_to(OUT)), "name": name, "section": section, "width": width, "height": height, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
(OUT / "screenshots.json").write_text(json.dumps(items, indent=2) + "\n")
figures = []
for item in items:
    file = html.escape(item["file"], quote=True)
    title = html.escape(item["name"].replace("-", " ").replace("_", " "))
    figures.append(f'<figure data-platform="{item["platform"]}" data-section="{item["section"]}"><a href="{file}" target="_blank"><img src="{file}" loading="lazy" alt="{title}"></a><figcaption><small>{item["platform"].upper()} · {item["section"]}</small>{title}</figcaption></figure>')
(OUT / "index.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hadithly native preview</title>
<style>*{box-sizing:border-box}body{margin:0;background:#f5f5f7;color:#1c1c1e;font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}header,main{max-width:1480px;margin:auto;padding:36px 28px}h1{font-size:32px;letter-spacing:-.8px;margin:0 0 12px}p{max-width:760px;color:#60636b;line-height:1.5}nav{display:flex;gap:8px;flex-wrap:wrap;margin:24px 0}button{border:1px solid #d1d4dc;border-radius:24px;background:white;padding:10px 18px;font:inherit;cursor:pointer}button[aria-pressed=true]{background:#1c1c1e;color:white;border-color:#1c1c1e}main{padding-top:0;display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:28px}figure{margin:0;min-width:0}figure[hidden]{display:none}img{width:100%;height:auto;border-radius:24px;display:block;box-shadow:0 8px 28px #00000012}figcaption{padding:14px 4px;text-transform:capitalize;line-height:1.4}small{display:block;color:#60636b;font-size:11px;letter-spacing:.8px;margin-bottom:4px}a{color:inherit}footer{padding:32px;text-align:center;color:#60636b;font-size:13px}@media(prefers-color-scheme:dark){body{background:#101012;color:#f2f2f2}p,small,footer{color:#a0a0a8}button{background:#242426;color:#f2f2f2;border-color:#404044}button[aria-pressed=true]{background:white;color:#101012}}</style>
<header><h1>Hadithly, native preview</h1><p>Original captures from the iOS simulator and Android emulator. Welcome follows the system theme and detected language. Forms use plain surfaces; reader sheets and Saved share native controls. Reader, search, Saved and pricing fixtures use seeded data; onboarding loads the real daily hadith. No sign-in or email delivery was submitted.</p><nav aria-label="Platform"><button data-platform-filter="all" aria-pressed="true">Both platforms</button><button data-platform-filter="ios" aria-pressed="false">iOS</button><button data-platform-filter="android" aria-pressed="false">Android</button></nav><nav aria-label="Screens"><button data-section-filter="all" aria-pressed="true">All screens</button><button data-section-filter="Onboarding" aria-pressed="false">Onboarding</button><button data-section-filter="Auth" aria-pressed="false">Authentication</button><button data-section-filter="Reader" aria-pressed="false">Reader &amp; Saved</button><button data-section-filter="Navigation" aria-pressed="false">Navigation</button><button data-section-filter="Settings" aria-pressed="false">Settings</button><button data-section-filter="Paywall" aria-pressed="false">Pricing prototype</button><button data-section-filter="Normal RTL" aria-pressed="false">Normal RTL</button><button data-section-filter="Accessibility" aria-pressed="false">Large text</button></nav><p>Click a screenshot for its original size. Normal RTL uses default text sizes. Large-text accessibility captures are shown separately. The emulator keyboard language is a separate system preference.</p></header><main>''' + "\n".join(figures) + '''</main><footer>October 16, 2026 · Development UI verification. Device, account, store and native-copy review gates remain separate.</footer><script>let platform='all',section='all';document.querySelectorAll('button').forEach(button=>button.onclick=()=>{const isPlatform='platformFilter'in button.dataset,key=isPlatform?'platformFilter':'sectionFilter';if(isPlatform)platform=button.dataset[key];else section=button.dataset[key];document.querySelectorAll('button[data-'+(isPlatform?'platform':'section')+'-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));document.querySelectorAll('figure').forEach(f=>f.hidden=(platform!=='all'&&f.dataset.platform!==platform)||(section!=='all'&&f.dataset.section!==section))});</script></html>''')
print(f"Wrote {len(items)} original screenshots and the local gallery.")
