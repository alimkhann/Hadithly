#!/usr/bin/env python3
"""Verify scoped plural generation and rejection before partial writes."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class PluralCopyGeneratorTests(unittest.TestCase):
    def test_repeatability_preservation_and_lost_count_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def write(name, text):
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text); return path
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True)
            git('init', '-q')
            data = json.loads((ROOT / 'docs/a4-plural-copy.json').read_text())
            entries = {}
            for key, repair in data['ios_repairs'].items():
                entries[key] = {'comment': 'Keep metadata', 'localizations': {'en': {'variations': {'plural': {'other': {'stringUnit': {'state': 'translated', 'value': key}}}}}}}
                repair['expected_index_hash'] = hashlib.sha256(json.dumps(entries[key], sort_keys=True, ensure_ascii=False).encode()).hexdigest()
            entries['unrelated'] = {'value': 'indexed'}
            catalog = write('ios/Hadithly/Localizable.xcstrings', json.dumps({'strings': entries}, ensure_ascii=False, indent=2))
            git('add', 'ios/Hadithly/Localizable.xcstrings')
            index = git('show', ':ios/Hadithly/Localizable.xcstrings')
            work = json.loads(catalog.read_text()); work['strings']['unrelated']['value'] = 'Incoming bytes'; catalog.write_text(json.dumps(work, ensure_ascii=False, indent=2))
            source = write('docs/a4-plural-copy.json', json.dumps(data, ensure_ascii=False))
            script = write('scripts/sync-plural-copy.py', (ROOT / 'scripts/sync-plural-copy.py').read_text())
            for locale in data['ios_repairs'][data['keys'][0]]['locales']:
                folder = {'en':'values', 'id':'values-in', 'es-419':'values-b+es+419', 'pt-BR':'values-pt-rBR'}.get(locale, 'values-'+locale)
                write('android/app/src/main/res/'+folder+'/strings.xml', '<resources>\n<string name="keep">Untouched</string>\n'+'\n'.join('<plurals name="'+name+'"><item quantity="other">%d old</item></plurals>' for name in data['android_resources'].values())+'\n</resources>')
            command = ['python3', str(script)]
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(git('show', ':ios/Hadithly/Localizable.xcstrings'), index)
            self.assertEqual(json.loads(catalog.read_text())['strings']['unrelated'], work['strings']['unrelated'])
            self.assertIn('<string name="keep">Untouched</string>', (root/'android/app/src/main/res/values-ar/strings.xml').read_text())
            result = subprocess.run(command+['--check'], cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            before = {p:p.read_bytes() for p in [catalog, *root.glob('android/app/src/main/res/*/strings.xml')]}
            data['ios_repairs'][data['keys'][0]]['plural_localizations']['ru']['few'] = 'Lost argument'
            source.write_text(json.dumps(data))
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(all(p.read_bytes() == raw for p,raw in before.items()))

if __name__ == '__main__':
    unittest.main()
