#!/usr/bin/env python3
"""Build optimized iPhone development artifacts without changing Xcode project files."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess


def source_digest(root):
    source = hashlib.sha256()
    for name in sorted(subprocess.check_output(['git', 'ls-files', 'ios'], cwd=root, text=True).splitlines()):
        source.update(name.encode() + b'\0' + (root / name).read_bytes() + b'\0')
    return source.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--derived-data', type=Path, required=True)
    parser.add_argument('--source-packages', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-development-url', required=True)
    parser.add_argument('--build-for-testing', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    args.output.mkdir(parents=True, exist_ok=False)
    project = (root / 'ios/project.yml').read_text()
    team = re.search(r'DEVELOPMENT_TEAM: (\w+)', project).group(1)
    initial_source = source_digest(root)
    command = [
        'xcodebuild', '-project', str(root / 'ios/Hadithly.xcodeproj'),
        '-scheme', 'LA2Verification' if args.build_for_testing else 'Hadithly',
        '-configuration', 'Debug', '-destination', 'generic/platform=iOS',
        '-derivedDataPath', str(args.derived_data),
        '-clonedSourcePackagesDirPath', str(args.source_packages),
        '-disableAutomaticPackageResolution', 'SWIFT_OPTIMIZATION_LEVEL=-O',
        'SWIFT_COMPILATION_MODE=wholemodule', 'GCC_OPTIMIZATION_LEVEL=s',
        'DEBUG_INFORMATION_FORMAT=dwarf-with-dsym', f'DEVELOPMENT_TEAM={team}',
        'build-for-testing' if args.build_for_testing else 'build',
    ]
    with (args.output / 'build.log').open('w') as log:
        subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = args.derived_data / 'Build/Products/Debug-iphoneos/Hadithly.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != 'com.hadithly.app'
            or info.get('ConvexURL') != args.expected_development_url
            or info.get('DiagnosticsEnvironment') != 'development'):
        raise ValueError('Build is not the explicitly selected development app')
    signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                            capture_output=True, check=True)
    entitlements = plistlib.loads(signed.stdout)
    if (entitlements.get('com.apple.developer.devicecheck.appattest-environment') != 'development'
            or entitlements.get('get-task-allow') is not True):
        raise ValueError('Profiling requires development App Attest and debugger entitlements')
    binary = app / info['CFBundleExecutable']
    if source_digest(root) != initial_source:
        raise ValueError('iOS sources changed during the build; this artifact is not accepted')
    manifest = {
        'configuration': 'Debug with optimized Swift and C compilation',
        'swiftOptimization': '-O', 'swiftCompilation': 'wholemodule',
        'bundleIdentifier': info['CFBundleIdentifier'],
        'developmentURL': info['ConvexURL'],
        'diagnosticsEnvironment': info['DiagnosticsEnvironment'],
        'appAttestEnvironment': 'development', 'debuggerAttachAllowed': True,
        'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'iosTrackedSourceSHA256': initial_source,
        'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'note': 'Retains DEBUG compilation conditions and development entitlements. No app installation or project regeneration.',
    }
    (args.output / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Validated optimized development app: {app}')


if __name__ == '__main__':
    main()
