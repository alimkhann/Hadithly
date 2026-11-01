#!/usr/bin/env python3
"""Read public cached outline metadata into a private file outside the repository."""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deployment', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    target = args.output.resolve()
    if target.is_relative_to(root):
        parser.error('Keep the source metadata snapshot outside the repository')
    query = ('const rows = await ctx.db.query("collectionOutlines").take(8); '
             'if (rows.some(row => "packedVolumes" in row)) throw new Error("Legacy baseline required"); '
             'return JSON.stringify(rows.map(({collectionSlug,volumes,indexedAt}) => '
             '({collectionSlug,volumes,indexedAt})));')
    command = [str(root / 'backend/node_modules/.bin/convex'), 'run', '--deployment',
               args.deployment, '--inline-query', query, '--codegen', 'disable']
    try:
        result = subprocess.run(command, cwd=root / 'backend', stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, timeout=45)
        if result.returncode:
            raise ValueError()
        rows = json.loads(json.loads(result.stdout))
        if not isinstance(rows, list) or len(rows) != 7:
            raise ValueError()
        expected = {'bukhari', 'muslim', 'tirmidhi', 'sunan-nasai', 'abu-dawood',
                    'ibn-majah', 'mishkat-al-masabih'}
        if {row['collectionSlug'] for row in rows} != expected:
            raise ValueError()
        for row in rows:
            if (set(row) != {'collectionSlug', 'volumes', 'indexedAt'} or
                    not isinstance(row['volumes'], list) or
                    type(row['indexedAt']) not in (int, float) or not math.isfinite(row['indexedAt'])):
                raise ValueError()
        descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'w') as output:
            json.dump(rows, output, ensure_ascii=False)
    except (subprocess.SubprocessError, OSError, ValueError, TypeError, KeyError):
        parser.exit(1, 'Public outline snapshot capture failed; raw output withheld. Use a new private output path.\n')
    print('Captured seven public collection outlines; no user records or provider calls')


if __name__ == '__main__':
    main()
