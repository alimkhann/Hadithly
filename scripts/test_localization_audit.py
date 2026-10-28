#!/usr/bin/env python3
"""Regression checks for formatter argument loss, duplication and plural units."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import localization_audit as audit


class PlaceholderAuditTests(unittest.TestCase):
    def test_runtime_candidates_distinguish_missing_keys_and_debug_fixtures(self):
        rows = audit.runtime_literal_candidates('Text("Saved")\nButton("Missing") {}\n#if DEBUG\nText("Preview")\n#endif', 'ios', {'Saved'})
        self.assertEqual([row['category'] for row in rows], ['catalog-backed-runtime-unverified', 'missing-catalog-key', 'debug-fixture'])

    def test_runtime_candidates_keep_dynamic_and_direct_text_for_review(self):
        rows = audit.runtime_literal_candidates('Text("Page \\(number)")', 'ios', set())
        self.assertEqual(rows[0]['category'], 'dynamic-review')
        rows = audit.runtime_literal_candidates('nativeText("Known")\nnativeText("Missing")\nText(text = "English")', 'android', {'Known'})
        self.assertEqual([row['category'] for row in rows], ['catalog-backed-runtime-unverified', 'missing-native-mapping', 'direct-literal-review'])

    def test_non_debug_conditional_else_stays_in_review(self):
        rows = audit.runtime_literal_candidates('#if os(iOS)\nText("First")\n#else\nText("Second")\n#endif', 'ios', set())
        self.assertEqual([row['category'] for row in rows], ['missing-catalog-key', 'missing-catalog-key'])

    def test_runtime_inventory_includes_custom_title_wrappers(self):
        rows = audit.runtime_literal_candidates('ReaderSheetChrome(title: "Contents", palette: palette) {}\nQuietEmptyState(title: "Empty", message: "Details")\n.appNavigationTitle("Saved")', 'ios', {'Saved'})
        self.assertEqual([row['value'] for row in rows], ['Contents', 'Empty', 'Saved'])
        self.assertEqual([row['category'] for row in rows], ['missing-catalog-key', 'missing-catalog-key', 'catalog-backed-runtime-unverified'])

    def test_runtime_inventory_includes_policy_link_wrappers(self):
        swift = audit.runtime_literal_candidates('SettingsLinkRow(title: "Privacy Policy", subtitle: nil)', 'ios', {'Privacy Policy'})
        kotlin = audit.runtime_literal_candidates('PolicyRow(title = "Privacy Policy", onClick = {})', 'android', {'Privacy Policy'})
        self.assertEqual(swift[0]['category'], 'catalog-backed-runtime-unverified')
        self.assertEqual(kotlin[0]['category'], 'catalog-backed-runtime-unverified')

    def ios_failures(self, english, arabic):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / 'Localizable.xcstrings'
            catalog.write_text(json.dumps({'strings': {'message': {'localizations': {
                'en': {'stringUnit': {'value': english}},
                'ar': {'stringUnit': {'value': arabic}},
            }}}}))
            with patch.object(audit, 'IOS_CATALOG', catalog), patch.object(audit, 'WAVE1', ('en', 'ar')):
                return audit.audit_ios(True)[2]

    def test_implicit_arabic_count_is_exact_and_never_hides_lost_other_arguments(self):
        self.assertTrue(audit.implicit_plural_count('%lld hadiths', 'ar', 'two', '%lld hadiths', 'حديثان'))
        self.assertTrue(audit.implicit_plural_count('reader_hadith_count', 'ar', 'zero', '%d hadiths', 'لا أحاديث'))
        self.assertFalse(audit.implicit_plural_count('%lld hadiths', 'ar', 'other', '%lld hadiths', 'حديثان'))
        self.assertFalse(audit.implicit_plural_count('%lld hadiths', 'ar', 'two', '%lld hadiths', 'Changed wording'))
        self.assertFalse(audit.implicit_plural_count('%lld hadiths', 'ar', 'two', '%lld of %lld', 'حديثان'))
        self.assertFalse(audit.implicit_plural_count('unrelated', 'ar', 'two', '%d items', 'حديثان'))

    def test_ios_rejects_dropped_argument(self):
        self.assertTrue(self.ios_failures('%@ of %@', '%@'))

    def test_ios_rejects_extra_duplicate_argument(self):
        self.assertTrue(self.ios_failures('%1$@', '%1$@ %1$@'))

    def test_numbered_reordering_keeps_the_same_arguments(self):
        self.assertEqual(self.ios_failures('%@ of %@', '%2$@ / %1$@'), [])

    def test_percent_escape_is_not_a_formatter_argument(self):
        self.assertEqual(audit.placeholders('%%d and %d'), audit.placeholders('%d'))

    def test_android_rejects_empty_plural_without_formatter(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog = root / 'catalog.json'; catalog.write_text('{"strings":{}}')
            for folder, value in [('values', 'Items'), ('values-ar', '')]:
                path = root / folder; path.mkdir()
                (path / 'extra.xml').write_text('<resources><plurals name="items"><item quantity="other">' + value + '</item></plurals></resources>')
            with patch.object(audit, 'IOS_CATALOG', catalog), patch.object(audit, 'ANDROID_RES', root), patch.object(audit, 'WAVE1', ('en', 'ar')):
                failures = audit.audit_android(True)[2]
            self.assertTrue(any('empty' in failure for failure in failures), failures)

    def test_android_checks_each_plural_quantity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalog = root / 'catalog.json'; catalog.write_text('{"strings":{}}')
            for folder, text in [('values', '<item quantity="one">%d item</item><item quantity="other">%d items</item>'),
                                 ('values-ar', '<item quantity="one">%d عنصر</item><item quantity="other">عناصر</item>')]:
                path = root / folder; path.mkdir()
                (path / 'extra.xml').write_text('<resources><plurals name="items">' + text + '</plurals></resources>')
            with patch.object(audit, 'IOS_CATALOG', catalog), patch.object(audit, 'ANDROID_RES', root), patch.object(audit, 'WAVE1', ('en', 'ar')):
                failures = audit.audit_android(True)[2]
            self.assertTrue(any('placeholder' in failure for failure in failures), failures)


if __name__ == '__main__':
    unittest.main()
