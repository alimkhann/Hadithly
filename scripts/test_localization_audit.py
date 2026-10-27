#!/usr/bin/env python3
"""Regression checks for formatter argument loss, duplication and plural units."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import localization_audit as audit


class PlaceholderAuditTests(unittest.TestCase):
    def ios_failures(self, english, arabic):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / 'Localizable.xcstrings'
            catalog.write_text(json.dumps({'strings': {'message': {'localizations': {
                'en': {'stringUnit': {'value': english}},
                'ar': {'stringUnit': {'value': arabic}},
            }}}}))
            with patch.object(audit, 'IOS_CATALOG', catalog), patch.object(audit, 'WAVE1', ('en', 'ar')):
                return audit.audit_ios(True)[2]

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
