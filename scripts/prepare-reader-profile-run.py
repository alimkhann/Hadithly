#!/usr/bin/env python3
"""Prepare one destination-only physical reader run without runtime checkers."""
import argparse
from pathlib import Path
import plistlib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--velocity', choices=['slow', 'fast'], required=True)
    parser.add_argument('--repetitions', type=int, choices=[1, 3], default=1,
                        help='Use one run per capture when cooling between the required three repetitions')
    parser.add_argument('--preset', choices=['ordinary', 'bilingual', 'large'],
                        help='Prepare reader typography through its settings UI instead of measuring')
    parser.add_argument('--hadith', help='Use Contents Go after applying a preset')
    args = parser.parse_args()
    if args.hadith and (not args.preset or not all(part.isdigit() and part for part in args.hadith.split('.'))):
        parser.error('A hadith jump requires a preset and a numeric reference')
    source = plistlib.loads(args.source.read_bytes())
    target = source['HadithlyUITests']
    for key in ['TestHostPath', 'TestBundlePath', 'UITargetAppPath', 'DependentProductPaths']:
        target.pop(key, None)
    target.update({
        'UseDestinationArtifacts': True,
        'TestHostBundleIdentifier': 'com.hadithly.app.uitests.xctrunner',
        'TestBundleDestinationRelativePath': 'PlugIns/HadithlyUITests.xctest',
        'UITargetAppBundleIdentifier': 'com.hadithly.app',
        'UITargetAppCommandLineArguments': [],
        'UITargetAppEnvironmentVariables': {},
        'OnlyTestIdentifiers': ['ReaderR6AUITests/testPhysicalLoadedReaderScrollingPerformance'],
        'UITargetAppPerformanceAntipatternCheckerEnabled': False,
        'UITargetAppMainThreadCheckerEnabled': False,
        'SystemAttachmentLifetime': 'keepNever',
        'PreferredScreenCaptureFormat': 'screenshots',
        'EnvironmentVariables': {
            'HADITHLY_PHYSICAL_SCROLL': '1', 'HADITHLY_SCROLL_SECONDS': '30',
            'HADITHLY_SCROLL_GESTURE': args.velocity, 'HADITHLY_SCROLL_TRACE': '1',
            'HADITHLY_SCROLL_REPETITIONS': str(args.repetitions),
        },
    })
    if args.preset:
        target['OnlyTestIdentifiers'] = ['ReaderR6AUITests/testPhysicalPrepareReaderProfileWorkload']
        target['EnvironmentVariables']['HADITHLY_READER_PROFILE_PRESET'] = args.preset
        if args.hadith:
            target['EnvironmentVariables']['HADITHLY_READER_PROFILE_HADITH'] = args.hadith
    result = {'HadithlyUITests': target, '__xctestrun_metadata__': source['__xctestrun_metadata__']}
    with args.output.open('xb') as output:
        output.write(plistlib.dumps(result))
    action = 'reader settings' if args.preset else 'gesture-only'
    print(f'Prepared {action} configuration; app installation and launch arguments are disabled.')


if __name__ == '__main__':
    main()
