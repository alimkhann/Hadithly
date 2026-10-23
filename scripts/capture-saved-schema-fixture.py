#!/usr/bin/env python3
"""Capture the synthetic Saved fixture from the d1c80bc native test binary."""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
import time


def inspect(connection):
    columns = {row[1] for row in connection.execute("PRAGMA table_info(ZGUESTSAVEDASSEMBLY)")}
    if not columns or {"ZACTIVEDATA", "ZRETIRINGDATA", "ZROWMODE"} & columns:
        return False
    row = connection.execute("SELECT ZLEASEDATA,ZCHECKPOINTDATA FROM ZGUESTSAVEDASSEMBLY LIMIT 1").fetchone()
    if not row:
        return False
    lease, checkpoint = (json.loads(value) for value in row)
    owner = lease["owner"]
    return (
        owner["key"] == "owner-a"
        and owner["subject"] == "subject-a"
        and "folding" in checkpoint["stage"]
        and checkpoint["position"]["nextOrdinal"] == 1005
        and connection.execute("SELECT COUNT(*) FROM ZGUESTSAVEDFACTROW").fetchone()[0] == 1005
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--containers", type=Path, help="Simulator Data/Application directory to watch")
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as temporary:
        database = Path(temporary) / "saved.store"
        if args.verify:
            raw = gzip.decompress(args.output.read_bytes())
            database.write_bytes(raw)
            with sqlite3.connect(database) as connection:
                if not inspect(connection) or b"/Users/" in raw:
                    raise SystemExit("Unexpected fixture schema, state or local path")
            print("Prior Saved schema and 1,005 synthetic facts verified; SHA256", hashlib.sha256(raw).hexdigest())
            return
        if not args.containers:
            parser.error("--containers is required for capture")
        args.containers = args.containers.resolve()
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            for source in args.containers.glob("*/tmp/*/large.store"):
                try:
                    with sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=0.2) as connection:
                        if not inspect(connection):
                            continue
                        with sqlite3.connect(database) as target:
                            connection.backup(target)
                    with sqlite3.connect(database) as target:
                        if not inspect(target):
                            continue
                        target.execute("PRAGMA journal_mode=DELETE")
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    args.output.write_bytes(gzip.compress(database.read_bytes(), mtime=0))
                    print("Captured prior Saved schema at terminal fold boundary")
                    return
                except (sqlite3.Error, OSError, ValueError):
                    continue
            time.sleep(0.01)
        raise SystemExit("No terminal prior-schema fixture observed")


if __name__ == "__main__":
    main()
