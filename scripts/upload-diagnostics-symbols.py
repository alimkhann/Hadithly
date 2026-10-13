#!/usr/bin/env python3
"""Upload one owner-authorized dSYM, without source contents or local user paths."""
import argparse
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("dsym", type=Path)
parser.add_argument("--token-file", type=Path)
parser.add_argument("--dry-run", action="store_true")
args = parser.parse_args()
assert args.dsym.name.endswith(".dSYM") and args.dsym.is_dir(), "Expected a dSYM bundle"
files = list((args.dsym / "Contents/Resources/DWARF").iterdir())
assert len(files) == 1 and files[0].is_file(), "Expected one binary's symbols"
assert b"/Users/" not in files[0].read_bytes(), "Rebuild with neutral debug/file prefix maps before upload"
environment = os.environ.copy()
environment["SENTRY_URL"] = "https://de.sentry.io"
if not args.dry_run:
    assert args.token_file and args.token_file.stat().st_mode & 0o077 == 0, "Use an owner-approved token file with mode 600"
    environment["SENTRY_AUTH_TOKEN"] = args.token_file.read_text().strip()
command = ["npx", "--yes", "@sentry/cli@3.8.0", "debug-files", "upload", "--org", "alimkhan-yergebayev",
           "--project", "hadithly-ios", "--type", "dsym", "--no-sources", "--wait-for", "60"]
if args.dry_run:
    command.append("--no-upload")
subprocess.run(command + [str(args.dsym)], env=environment, check=True)
