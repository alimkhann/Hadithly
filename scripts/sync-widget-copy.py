#!/usr/bin/env python3
"""Generate shared native widget copy and Android picker/channel resources."""
import argparse
import json
from pathlib import Path
import re
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
source = json.loads((ROOT / 'docs/a4-widget-copy.json').read_text())
keys, locales = source['keys'], source['locales']
assert len(locales) == 15 and len(set(keys)) == len(keys)
for locale, values in locales.items():
    assert set(values) == set(keys) and all(values.values()), locale
    for key in keys:
        assert sorted(re.findall(r'%\d+\$@', values[key])) == sorted(re.findall(r'%\d+\$@', locales['en'][key])), (locale, key)
q = lambda value: json.dumps(value, ensure_ascii=False)
base = lambda locale: locale.split('-')[0]
marker = '// BEGIN GENERATED WIDGET COPY'
end_marker = '// END GENERATED WIDGET COPY'

def output(path, text):
    if args.check:
        assert path.read_text() == text, f'Widget copy out of date: {path.relative_to(ROOT)}'
    else:
        path.write_text(text)

def replace_block(path, old_name, text):
    original = path.read_text()
    if marker in original:
        start = original.index(marker); end = original.index(end_marker, start) + len(end_marker)
    else:
        start = original.index(old_name); depth = 0; end = start
        for index in range(original.index('{', start), len(original)):
            if original[index] == '{': depth += 1
            elif original[index] == '}':
                depth -= 1
                if depth == 0: end = index + 1; break
    output(path, original[:start] + text + original[end:])

swift_rows = []
kotlin_rows = []
for locale, values in locales.items():
    swift_rows.append('        ' + q(base(locale)) + ': [' + ', '.join('.' + key + ': ' + q(values[key]) for key in keys) + ']')
    kotlin_rows.append('        ' + q(base(locale)) + ' to mapOf(' + ', '.join('Key.' + key + ' to ' + q(re.sub(r'%(\d+\$)?@', lambda m: '%' + (m[1] or '') + 's', values[key])).replace('$', r'\$') for key in keys) + ')')
swift = marker + '''
// Generated interface drafts; native review pending.
enum WidgetCopy {
    enum Key: String { case ''' + ', '.join(keys) + ''' }
    private static let values: [String: [Key: String]] = [
''' + ',\n'.join(swift_rows) + '''
    ]
    static func text(_ key: Key, locale: String) -> String {
        let language = Locale(identifier: locale).language.languageCode?.identifier ?? "en"
        return values[language]?[key] ?? values["en"]![key]!
    }
    static func format(_ key: Key, locale: String, numbers: Int...) -> String {
        let localeValue = Locale(identifier: locale)
        let arguments = numbers.map { $0.formatted(.number.locale(localeValue)) as CVarArg }
        return String(format: text(key, locale: locale), locale: localeValue, arguments: arguments)
    }
}
''' + end_marker
kotlin = marker + '''
// Generated interface drafts; native review pending.
object WidgetCopy {
    enum class Key { ''' + ', '.join(keys) + ''' }
    private val values = mapOf(
''' + ',\n'.join(kotlin_rows) + '''
    )
    fun text(key: Key, locale: String): String {
        val language = java.util.Locale.forLanguageTag(locale.replace('_', '-')).language.let { if (it == "in") "id" else it }
        return (values[language] ?: values.getValue("en")).getValue(key)
    }
    fun format(key: Key, locale: String, vararg numbers: Int): String {
        val localeValue = java.util.Locale.forLanguageTag(locale.replace('_', '-'))
        val formatter = java.text.NumberFormat.getIntegerInstance(localeValue)
        return String.format(localeValue, text(key, locale), *numbers.map { formatter.format(it) }.toTypedArray())
    }
}
''' + end_marker
replace_block(ROOT / 'ios/Hadithly/Core/Widgets/WidgetSnapshot.swift', 'enum DailyWidgetCopy', swift)
replace_block(ROOT / 'android/app/src/main/kotlin/com/hadithly/app/core/widgets/WidgetSnapshotStore.kt', 'object DailyWidgetCopy', kotlin)
resources = {'widget_daily_title': 'dailyTitle', 'widget_daily_description': 'dailyGalleryDescription',
             'widget_continue_title': 'continueTitle', 'widget_continue_description': 'continueGalleryDescription',
             'notification_daily_channel_title': 'notificationChannelTitle', 'notification_daily_channel_description': 'notificationChannelDescription'}
for locale, values in locales.items():
    folder = {'en': 'values', 'id': 'values-in', 'es-419': 'values-b+es+419', 'pt-BR': 'values-pt-rBR'}.get(locale, 'values-' + locale)
    rows = []
    for name, key in resources.items():
        value = escape(values[key]).replace("'", r"\'").replace('"', r'\"')
        rows.append(f'    <string name="{name}">{value}</string>')
    output(ROOT / 'android/app/src/main/res' / folder / 'widget_copy.xml', '<resources>\n    <!-- Generated interface drafts; native review pending. -->\n' + '\n'.join(rows) + '\n</resources>\n')
print(f'Widget copy: {len(keys)} keys x {len(locales)} locales; native review pending.')
