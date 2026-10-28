#!/usr/bin/env python3
"""Exercise exact catalog-index repairs in an isolated Git repository."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('stage-new-catalog-copy.py')
CATALOG = 'ios/Hadithly/Localizable.xcstrings'


class CatalogStagingTests(unittest.TestCase):
    def test_repairs_require_hash_and_locale_scope_and_preserve_other_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True)
            git('init', '-q')
            path = root / CATALOG; path.parent.mkdir(parents=True)
            base = {'strings': {'message': {'comment': 'keep metadata', 'localizations': {
                'en': {'stringUnit': {'state': 'needs_review', 'value': 'Share'}},
                'ar': {'stringUnit': {'state': 'needs_review', 'value': 'Wrong'}},
            }}, 'unrelated': {'value': 'indexed'}}}
            path.write_text(json.dumps(base, indent=2))
            git('add', CATALOG)
            original_index = git('show', ':' + CATALOG)
            work = json.loads(path.read_text())
            work['strings']['message']['localizations']['ar']['stringUnit']['value'] = 'Correct'
            work['strings']['unrelated']['value'] = 'incoming work'
            path.write_text(json.dumps(work, indent=2))
            expected = hashlib.sha256(json.dumps(base['strings']['message'], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
            source = {'keys': ['message'], 'locales': {'ar': ['Correct']}, 'ios_repairs': {'message': {'expected_index_hash': expected, 'locales': ['ar']}}}
            source_path = root / 'copy.json'; source_path.write_text(json.dumps(source))
            script = root / 'scripts' / SCRIPT.name; script.parent.mkdir(); shutil.copy(SCRIPT, script)
            command = ['python3', str(script), '--source', 'copy.json', '--stage']
            def run(extra=()):
                return subprocess.run(command + list(extra), cwd=root, capture_output=True, text=True)
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), original_index)
            source['ios_repairs']['message']['expected_index_hash'] = 'bad hash'
            source_path.write_text(json.dumps(source))
            self.assertNotEqual(run(['--repair-existing']).returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), original_index)
            source['ios_repairs']['message']['expected_index_hash'] = expected
            source_path.write_text(json.dumps(source))
            work['strings']['message']['localizations']['en']['stringUnit']['value'] = 'Accidental English edit'
            path.write_text(json.dumps(work, indent=2))
            self.assertNotEqual(run(['--repair-existing']).returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), original_index)
            work['strings']['message']['localizations']['en'] = base['strings']['message']['localizations']['en']
            path.write_text(json.dumps(work, indent=2)); incoming_bytes = path.read_bytes()
            result = run(['--repair-existing']); self.assertEqual(result.returncode, 0, result.stderr)
            staged = json.loads(git('show', ':' + CATALOG))
            self.assertEqual(staged['strings']['message'], work['strings']['message'])
            self.assertEqual(staged['strings']['unrelated'], base['strings']['unrelated'])
            self.assertEqual(path.read_bytes(), incoming_bytes)
            staged_bytes = git('show', ':' + CATALOG)
            self.assertEqual(run(['--repair-existing']).returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), staged_bytes)

            forms = {'one': '%lld حديث', 'two': 'حديثان', 'other': '%lld حديث'}
            source['ios_repairs']['message']['expected_index_hash'] = hashlib.sha256(
                json.dumps(staged['strings']['message'], sort_keys=True, ensure_ascii=False).encode()
            ).hexdigest()
            source['ios_repairs']['message']['plural_localizations'] = {'ar': forms}
            source_path.write_text(json.dumps(source))
            work['strings']['message']['localizations']['ar'] = {'variations': {'plural': {
                quantity: {'stringUnit': {'state': 'needs_review', 'value': value}}
                for quantity, value in forms.items()
            }}}
            path.write_text(json.dumps(work, indent=2)); incoming_bytes = path.read_bytes()
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), staged_bytes)
            work['strings']['message']['comment'] = 'unrelated metadata'
            path.write_text(json.dumps(work, indent=2))
            self.assertNotEqual(run(['--repair-existing']).returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), staged_bytes)
            work['strings']['message']['comment'] = 'keep metadata'
            path.write_bytes(incoming_bytes)
            result = run(['--repair-existing']); self.assertEqual(result.returncode, 0, result.stderr)
            staged = json.loads(git('show', ':' + CATALOG))
            self.assertEqual(staged['strings']['message'], work['strings']['message'])
            self.assertEqual(staged['strings']['unrelated'], base['strings']['unrelated'])
            self.assertEqual(path.read_bytes(), incoming_bytes)
            staged_bytes = git('show', ':' + CATALOG)
            self.assertEqual(run(['--repair-existing']).returncode, 0)
            self.assertEqual(git('show', ':' + CATALOG), staged_bytes)


if __name__ == '__main__':
    unittest.main()
