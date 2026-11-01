import copy
from pathlib import Path
import plistlib
import runpy
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent


class ReaderProfileConfigurationTests(unittest.TestCase):
    def test_generated_configuration_cannot_install_or_inject_a_profiler(self):
        source = {
            'HadithlyTests': {}, '__xctestrun_metadata__': {'FormatVersion': 1},
            'HadithlyUITests': {
                'TestHostPath': '/build/runner', 'TestBundlePath': '/build/tests',
                'UITargetAppPath': '/build/app', 'DependentProductPaths': ['/build/app'],
                'UITargetAppEnvironmentVariables': {'HADITHLY_UI_TESTING': '1'},
                'UITargetAppCommandLineArguments': ['-FreshInstallForUITest'],
                'EnvironmentVariables': {'DYLD_INSERT_LIBRARIES': '/libRPAC.dylib', 'PERFC_ENABLE_PROFILE_MODE': '1'},
                'UITargetAppPerformanceAntipatternCheckerEnabled': True,
            },
        }
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); original = path / 'source.xctestrun'; output = path / 'clean.xctestrun'
            original.write_bytes(plistlib.dumps(source))
            subprocess.run([sys.executable, str(SCRIPTS / 'prepare-reader-profile-run.py'),
                            '--source', str(original), '--output', str(output), '--velocity', 'fast'],
                           check=True, capture_output=True)
            actual = plistlib.loads(output.read_bytes())
            self.assertNotIn('HadithlyTests', actual)
            target = actual['HadithlyUITests']
            for key in ['TestHostPath', 'TestBundlePath', 'UITargetAppPath', 'DependentProductPaths']:
                self.assertNotIn(key, target)
            self.assertEqual(target['UITargetAppCommandLineArguments'], [])
            self.assertEqual(target['UITargetAppEnvironmentVariables'], {})
            self.assertFalse(target['UITargetAppPerformanceAntipatternCheckerEnabled'])
            self.assertNotIn('DYLD_INSERT_LIBRARIES', target['EnvironmentVariables'])
            self.assertTrue(target['UseDestinationArtifacts'])

    def test_unsafe_config_is_rejected_before_any_device_command(self):
        target = {
            'UseDestinationArtifacts': True, 'UITargetAppBundleIdentifier': 'com.hadithly.app',
            'EnvironmentVariables': {'HADITHLY_PHYSICAL_SCROLL': '1', 'DYLD_INSERT_LIBRARIES': '/libRPAC.dylib'},
            'OnlyTestIdentifiers': ['ReaderR6AUITests/testPhysicalLoadedReaderScrollingPerformance'],
            'UITargetAppPerformanceAntipatternCheckerEnabled': True,
        }
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); config = path / 'unsafe.xctestrun'; output = path / 'must-not-be-created'
            config.write_bytes(plistlib.dumps({'HadithlyUITests': target}))
            result = subprocess.run([
                sys.executable, str(SCRIPTS / 'run-reader-device-scroll.py'), '--device', 'must-not-contact',
                '--xctestrun', str(config), '--output', str(output), '--allow-physical-scroll', '--trace',
            ], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('disable runtime checkers', result.stderr)
            self.assertFalse(output.exists())

    def test_matching_requires_same_content_and_display_not_preference_timestamp(self):
        require_same = runpy.run_path(str(SCRIPTS / 'run-reader-device-scroll.py'))['require_same_workload']
        baseline = {key: 'same' for key in ['collection', 'volume', 'pageIndex', 'pageKey', 'contentVersion',
                    'hadiths', 'textSHA256', 'textBytes', 'automaticGenerationEnabled',
                    'lowPowerMode', 'thermalState', 'maximumFramesPerSecond']}
        baseline['preferences'] = {'arabicFontSize': 18, 'updatedAt': 1}
        later = copy.deepcopy(baseline); later['preferences']['updatedAt'] = 2
        require_same(later, baseline)
        later['preferences']['arabicFontSize'] = 40
        with self.assertRaisesRegex(ValueError, 'preferences'):
            require_same(later, baseline)
        later = copy.deepcopy(baseline); later['textSHA256'] = 'different'
        with self.assertRaisesRegex(ValueError, 'textSHA256'):
            require_same(later, baseline)


if __name__ == '__main__':
    unittest.main()
