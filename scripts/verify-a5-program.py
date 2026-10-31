#!/usr/bin/env python3
"""Verify A5 source scope, incoming bytes, retained gates and native result readbacks."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def git(*args):
    return subprocess.check_output(['git', *args])


def sha(data):
    return hashlib.sha256(data).hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ios', action='append', type=Path, default=[])
parser.add_argument('--android', action='append', type=Path, default=[])
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
record = json.loads(Path('docs/verification/a5-completion/baseline.json').read_text())
baseline = record['baseline']
incoming = record['incoming_sha256']
allowed = {
    'ios/Hadithly/App/RootView.swift',
    'ios/Hadithly/Core/ReadingPosition/ReadingPosition.swift',
    'ios/Hadithly/Core/Theme/ReaderPalette.swift',
    'ios/Hadithly/Features/Reader/ReaderModel.swift',
    'ios/Hadithly/Features/Reader/ReaderSheets.swift',
    'ios/Hadithly/Features/Reader/ReaderView.swift',
    'ios/Hadithly/Features/Settings/SettingsView.swift',
    'ios/HadithlyTests/ReaderR4Tests.swift',
    'ios/HadithlyTests/ReadingPositionTests.swift',
    'ios/HadithlyUITests/ReaderR5UITests.swift',
    'ios/HadithlyUITests/NativeFinishingUITests.swift',
    'ios/HadithlyUITests/ReaderPagingUITests.swift',
    'ios/HadithlyUITests/ReaderR6AUITests.swift',
    'ios/HadithlyUITests/LanguageSwitchUITests.swift',
    'android/app/src/main/kotlin/com/hadithly/app/core/data/ReadingPosition.kt',
    'android/app/src/main/kotlin/com/hadithly/app/core/preferences/ReaderPreferences.kt',
    'android/app/src/main/kotlin/com/hadithly/app/features/reader/ReaderViewModel.kt',
    'android/app/src/main/kotlin/com/hadithly/app/features/reader/ReaderScreen.kt',
    'android/app/src/main/kotlin/com/hadithly/app/features/saved/SavedUndoBanner.kt',
    'android/app/src/androidTest/kotlin/com/hadithly/app/features/reader/ContentsNavigationTest.kt',
    'android/app/src/androidTest/kotlin/com/hadithly/app/features/reader/ReaderProgressObservationTest.kt',
    'android/app/src/androidTest/kotlin/com/hadithly/app/features/reader/ReaderR6AQuietTest.kt',
    'android/app/src/androidTest/kotlin/com/hadithly/app/features/settings/LanguageSwitchTest.kt',
    'android/app/src/test/kotlin/com/hadithly/app/ReaderR4Test.kt',
    'android/app/src/test/kotlin/com/hadithly/app/ReaderR6ATest.kt',
    'android/app/src/test/kotlin/com/hadithly/app/ReadingPositionTest.kt',
    'scripts/verify-a5-program.py',
    'docs/A5_REQUIREMENT_AUDIT.md', 'docs/A5_READER_CONTROLS.md',
    'docs/A5_CONTENTS_NAVIGATION.md', 'docs/NEXT_SESSION_PROMPT.md',
    'docs/PLAN.md', 'docs/PRODUCT_PROGRAM.md', 'docs/SESSION_PROMPTS.md',
}
for path, expected in incoming.items():
    assert sha(Path(path).read_bytes()) == expected, 'Incoming bytes changed: ' + path
    assert git('show', ':' + path) == git('show', baseline + ':' + path), 'Incoming staged: ' + path
changed = set(git('diff', '--name-only', baseline).decode().splitlines())
untracked = set(git('ls-files', '--others', '--exclude-standard').decode().splitlines())
scoped = changed - set(incoming)
assert not {p for p in scoped if p not in allowed and not p.startswith('docs/verification/a5-completion/')}, sorted(scoped)
assert not {p for p in untracked if p not in allowed and not p.startswith(('docs/verification/a5-completion/', 'scripts/__pycache__/'))}, sorted(untracked)
for path, marker in [('docs/PLAN.md', '## A4 local closure, October 31'),
                     ('docs/PRODUCT_PROGRAM.md', '## Owner order, October 26')]:
    before = git('show', baseline + ':' + path).decode()
    after = Path(path).read_text()
    # The owner's expanded goal authorizes the A5 engineering checkbox only.
    after = after.replace('- [x] A5. Resolve reproduced', '- [ ] A5. Resolve reproduced')
    assert before[before.index(marker):] == after[after.index(marker):], 'Historical requirements changed: ' + path
preserved = {}
for prefix in ['backend', 'android/app/src/main/res',
               'ios/Hadithly/Features/Saved', 'android/app/src/main/kotlin/com/hadithly/app/features/sync']:
    assert not git('diff', baseline, '--', prefix), prefix
    preserved[prefix] = True
for path in ['docs/A2_WRAP_UP.md', 'docs/A4_REQUIREMENT_AUDIT.md', 'docs/OPEN_GATES.md',
             'docs/C_NATIVE_REFINEMENTS.md', 'docs/D_WEBSITE_REDESIGN.md', 'docs/POST_GOAL_BACKLOG.md']:
    assert Path(path).read_bytes() == git('show', baseline + ':' + path), path
    preserved[path] = sha(Path(path).read_bytes())
staged = git('diff', '--cached', '--name-only').decode().splitlines()
assert not any('__pycache__' in p or p.endswith(('.pyc', '.xcresult')) for p in staged)
results = []
for bundle in args.ios:
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)]))
    tree = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(bundle)]))
    def cases_in(node):
        if node.get('nodeType') == 'Test Case':
            yield {'name': node['nodeIdentifier'], 'result': node['result']}
        for child in node.get('children', []):
            yield from cases_in(child)
    cases = [case for node in tree['testNodes'] for case in cases_in(node)]
    assert len(cases) == summary['totalTestCount'] > 0, bundle
    results.append({'platform': 'ios', 'path': str(bundle), 'summary': summary, 'cases': cases})
for report in args.android:
    cases = list(ET.parse(report).getroot().iter('testcase'))
    assert cases, report
    results.append({'platform': 'android', 'path': str(report), 'sha256': sha(report.read_bytes()),
                    'tests': len(cases), 'cases': [{'class': c.get('classname'), 'name': c.get('name'),
                    'passed': c.find('failure') is None and c.find('error') is None and c.find('skipped') is None,
                    'failure': c.find('failure').get('message') if c.find('failure') is not None else None} for c in cases]})
output = {'baseline': baseline, 'incoming_working_bytes_preserved': incoming,
          'incoming_files_unstaged': True, 'source_scope': sorted(scoped),
          'source_sha256': {p: sha(Path(p).read_bytes()) for p in sorted(allowed) if Path(p).is_file()},
          'preserved': preserved, 'historical_requirements_preserved_except_authorized_A5_checkbox': True,
          'native_results': results, 'targets': {k: record[k] for k in ['ios_simulator', 'android_serial']},
          'limits': 'Controlled native simulator/emulator fixtures and isolated local stores/fake transports. No live, authenticated, physical, language-review or full accessibility acceptance.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print('A5 scope, incoming bytes, retained requirements and supplied native results verified.')
