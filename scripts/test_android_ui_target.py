#!/usr/bin/env python3
"""Prove the UI runner never selects implicit or physical targets."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('android_ui_runner', Path(__file__).with_name('run-android-ui-tests.py'))
runner = importlib.util.module_from_spec(spec); spec.loader.exec_module(runner)

class AndroidUITargetTests(unittest.TestCase):
    def test_rejects_physical_missing_and_multiple_targets(self):
        for serial in ['', 'physical-phone', 'emulator-5554,physical-phone', 'emulator-5554 emulator-5556']:
            with self.assertRaises(ValueError): runner.command(serial, ['com.example.Test#case'])

    def test_pins_the_task_serial_and_requires_cases(self):
        command = runner.command('emulator-5554', ['com.example.Test#case'])
        self.assertEqual(command[0:2], ['./gradlew', 'connectedDebugAndroidTest'])
        self.assertNotIn('--serial',command)
        with self.assertRaises(ValueError): runner.command('emulator-5554', [])
        with self.assertRaises(ValueError): runner.command('emulator-5554', ['--all-devices'])

    def test_requires_emulator_property_before_gradle(self):
        with patch('sys.argv', ['runner', '--serial', 'emulator-5554', '--class', 'com.example.Test']), patch.object(runner.subprocess, 'check_output', side_effect=['device\n', '0\n']), patch.object(runner.subprocess, 'call') as gradle:
            with self.assertRaises(SystemExit): runner.main()
            gradle.assert_not_called()

    def test_overrides_ambient_serial_and_uses_explicit_adb(self):
        with patch('sys.argv', ['runner', '--serial', 'emulator-5554', '--class', 'com.example.Test']), patch.dict(runner.os.environ, {'ANDROID_SERIAL':'unrelated-phone'}), patch.object(runner.subprocess, 'check_output', side_effect=['device\n','1\n']) as adb, patch.object(runner.subprocess, 'call', return_value=0) as gradle:
            self.assertEqual(runner.main(),0)
            self.assertTrue(all(call.args[0][1:3] == ['-s','emulator-5554'] for call in adb.call_args_list))
            self.assertEqual(gradle.call_args.kwargs['env']['ANDROID_SERIAL'],'emulator-5554')
            self.assertNotIn('--serial',gradle.call_args.args[0])

if __name__ == '__main__': unittest.main()
