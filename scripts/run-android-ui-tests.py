#!/usr/bin/env python3
"""Run selected instrumentation cases on one verified emulator."""
import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def command(serial, classes):
    if not re.fullmatch(r'emulator-[0-9]+', serial):
        raise ValueError('UI verification requires one emulator serial; physical and multiple targets are rejected')
    if not classes or any(not re.fullmatch(r'[A-Za-z0-9_.$]+(?:#[A-Za-z0-9_]+)?', name) for name in classes):
        raise ValueError('Select at least one package.Class or package.Class#method')
    return ['./gradlew', 'connectedDebugAndroidTest',
            '-Pandroid.testInstrumentationRunnerArguments.class=' + ','.join(classes)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--class', dest='classes', action='append', required=True)
    args = parser.parse_args()
    try:
        gradle = command(args.serial, args.classes)
        sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
        adb = str(sdk / 'platform-tools/adb')
        def read(*parts):
            return subprocess.check_output([adb, '-s', args.serial, *parts], text=True, timeout=15).strip()
        if read('get-state') != 'device' or read('shell', 'getprop', 'ro.kernel.qemu') != '1':
            raise ValueError('The selected target is not a running emulator')
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(2, str(error) + '\n')
    environment = dict(os.environ, ANDROID_SERIAL=args.serial)
    print(f'Running {len(args.classes)} selected UI case/class entries on {args.serial}', flush=True)
    return subprocess.call(gradle, cwd=ROOT / 'android', env=environment)


if __name__ == '__main__':
    raise SystemExit(main())
