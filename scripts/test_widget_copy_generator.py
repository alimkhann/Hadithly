#!/usr/bin/env python3
"""Check repeatable widget generation and rejection before partial writes."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('sync-widget-copy.py')
SOURCE = Path(__file__).resolve().parents[1] / 'docs/a4-widget-copy.json'

class WidgetCopyGeneratorTests(unittest.TestCase):
    def test_generation_preserves_models_checks_idempotence_and_rejects_lost_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def write(path, text):
                p = root / path; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text); return p
            script = write('scripts/sync-widget-copy.py', SCRIPT.read_text())
            source = write('docs/a4-widget-copy.json', SOURCE.read_text())
            swift = write('ios/Hadithly/Core/Widgets/WidgetSnapshot.swift', 'struct Before {}\nenum DailyWidgetCopy { static let old = "old" }\nstruct After {}\n')
            kotlin = write('android/app/src/main/kotlin/com/hadithly/app/core/widgets/WidgetSnapshotStore.kt', 'class Before\nobject DailyWidgetCopy { val old = "old" }\nclass After\n')
            data = json.loads(source.read_text())
            for locale in data['locales']:
                folder = {'en':'values', 'id':'values-in', 'es-419':'values-b+es+419', 'pt-BR':'values-pt-rBR'}.get(locale, 'values-'+locale)
                (root / 'android/app/src/main/res' / folder).mkdir(parents=True)
            command = ['python3', str(script)]
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(swift.read_text().startswith('struct Before {}\n'))
            self.assertTrue(swift.read_text().endswith('\nstruct After {}\n'))
            self.assertTrue(kotlin.read_text().startswith('class Before\n'))
            self.assertTrue(kotlin.read_text().endswith('\nclass After\n'))
            self.assertIn('%1\\$s', kotlin.read_text())
            self.assertTrue((root / 'android/app/src/main/res/values-in/widget_copy.xml').exists())
            result = subprocess.run(command + ['--check'], cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            before = {p: p.read_bytes() for p in [swift, kotlin, *root.glob('android/app/src/main/res/*/widget_copy.xml')]}
            data['locales']['ar']['continueProgressTotal'] = 'Dropped count argument'
            source.write_text(json.dumps(data))
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(all(p.read_bytes() == content for p, content in before.items()))

if __name__ == '__main__':
    unittest.main()
