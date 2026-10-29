#!/usr/bin/env python3
"""Exercise indexed-copy reuse in an isolated Git repository."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('generate-ui-polish-copy.py')
LOCALES = ['en', 'ar', 'ru', 'kk', 'ky', 'uz', 'tr', 'id', 'ur', 'fr', 'es-419', 'pt-BR', 'sw', 'hi', 'bn']


class IndexedCopyTests(unittest.TestCase):
    def test_reuse_preserves_working_catalog_updates_aliases_and_escapes_kotlin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def write(path, text):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
                return target
            def git(*arguments):
                return subprocess.run(['git', *arguments], cwd=root, check=True, capture_output=True, text=True)
            git('init', '-q')
            key = 'Keep $amount and ${total}: %1$@ %2$lld'
            catalog = {'strings': {key: {'localizations': {locale: {'stringUnit': {'value': locale + ' %1$@ %2$lld'}} for locale in LOCALES}}}}
            catalog_path = write('ios/Hadithly/Localizable.xcstrings', json.dumps(catalog))
            git('add', 'ios')
            catalog_path.write_text('{"incoming":"catalog bytes"}')
            helper = write('android/app/src/main/kotlin/com/hadithly/app/core/preferences/NativeCopy.kt', 'when(source) {\n    ' + json.dumps(key) + ' -> R.string.old\n    else -> null\n}\n')
            for locale in LOCALES:
                folder = {'en': 'values', 'es-419': 'values-b+es+419', 'pt-BR': 'values-pt-rBR', 'id': 'values-in'}.get(locale, 'values-' + locale)
                write('android/app/src/main/res/' + folder + '/strings.xml', '<resources>\n    <string name="untouched">Keep me</string>\n</resources>\n')
            source = {'keys': [key], 'locales': LOCALES, 'reuse_indexed_ios': True, 'android_resources': {key: [{'name': 'first', 'file': 'strings.xml'}, {'name': 'second', 'file': 'extra.xml'}]}}
            write('copy.json', json.dumps(source))
            script = root / 'scripts/generate-ui-polish-copy.py'; script.parent.mkdir(); shutil.copy(SCRIPT, script)
            command = ['python3', str(script), '--source', 'copy.json', '--android-only']
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(catalog_path.read_text(), '{"incoming":"catalog bytes"}')
            for locale in LOCALES:
                folder = {'en': 'values', 'es-419': 'values-b+es+419', 'pt-BR': 'values-pt-rBR', 'id': 'values-in'}.get(locale, 'values-' + locale)
                for filename, name in [('strings.xml', 'first'), ('extra.xml', 'second')]:
                    xml = (root / 'android/app/src/main/res' / folder / filename).read_text()
                    self.assertIn('name="' + name + '"', xml)
                    self.assertIn(locale + ' %1$s %2$d', xml)
            mapping = helper.read_text()
            self.assertEqual(mapping.count('R.string.first'), 1)
            self.assertNotIn('R.string.old', mapping)
            self.assertIn('Keep \\$amount and \\${total}: %1\\$@', mapping)
            result = subprocess.run(command + ['--check'], cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
