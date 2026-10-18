#!/usr/bin/env python3
"""Generate actual local-backend first-reading outcomes and check both client fixtures."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
names = ["starter-en", "starter-ru", "daily-ru", "original-ar", "unavailable-ru"]
destinations = [ROOT / "testdata/first-reading", ROOT / "android/app/src/androidTest/assets/first-reading"]
with tempfile.TemporaryDirectory(prefix="hadithly-first-reading-contract-") as directory:
    subprocess.run(["npm", "test", "--", "convex/firstReading.test.ts"], cwd=ROOT / "backend", check=True,
                   env={**os.environ, "HADITHLY_FIRST_READING_FIXTURE_DIR": directory}, capture_output=True)
    for name in names:
        source = Path(directory, name + ".json")
        value = json.loads(source.read_text())
        for destination in destinations:
            target = destination / source.name
            if args.write:
                destination.mkdir(parents=True, exist_ok=True)
                target.write_text(source.read_text())
            else:
                assert target.exists() and json.loads(target.read_text()) == value, f"Stale first-reading fixture: {target}"
print(f"{'Wrote' if args.write else 'Verified'} {len(names)} real local-backend outcomes for both native clients.")
