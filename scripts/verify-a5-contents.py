#!/usr/bin/env python3
"""Read back A5 native results and prove the bounded source/preservation scope."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def git(*args):
    return subprocess.check_output(['git', *args])


def digest(data):
    return hashlib.sha256(data).hexdigest()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ios', action='append', default=[], type=Path)
parser.add_argument('--android', action='append', default=[], type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
record = json.loads(Path('docs/verification/a5-contents/baseline.json').read_text())
baseline = record['baseline']
allowed = {
    'ios/Hadithly/App/RootView.swift',
    'ios/Hadithly/Features/Reader/ReaderModel.swift',
    'ios/Hadithly/Features/Reader/ReaderSheets.swift',
    'ios/Hadithly/Features/Reader/ReaderView.swift',
    'ios/HadithlyUITests/ReaderR5UITests.swift',
    'ios/HadithlyUITests/ReaderR6Round3UITests.swift',
    'android/app/src/main/kotlin/com/hadithly/app/features/reader/ReaderViewModel.kt',
    'android/app/src/androidTest/kotlin/com/hadithly/app/features/reader/ContentsNavigationTest.kt',
    'android/app/src/androidTest/kotlin/com/hadithly/app/features/reader/ReaderR6Round3Test.kt',
    'scripts/verify-a5-contents.py',
    'docs/A5_CONTENTS_NAVIGATION.md', 'docs/NEXT_SESSION_PROMPT.md',
    'docs/PLAN.md', 'docs/PRODUCT_PROGRAM.md', 'docs/SESSION_PROMPTS.md',
}
incoming = record['incoming_sha256']
for path, expected in incoming.items():
    assert digest(Path(path).read_bytes()) == expected, path
    assert git('show', ':' + path) == git('show', baseline + ':' + path), 'Incoming work staged: ' + path
changed = set(git('diff', '--name-only', baseline).decode().splitlines())
assert not (changed - allowed - set(incoming) - {p for p in changed if p.startswith('docs/verification/a5-contents/')}), sorted(changed)
# Historical checkpoints and the complete original requirements remain verbatim.
for path, marker in [('docs/PLAN.md', '## A4 local closure, October 31'),
                     ('docs/PRODUCT_PROGRAM.md', '## Owner order, October 26')]:
    before = git('show', baseline + ':' + path).decode()
    after = Path(path).read_text()
    assert before[before.index(marker):] == after[after.index(marker):], path
preserved = {}
for prefix in ['backend', 'ios/Hadithly/Core', 'android/app/src/main/kotlin/com/hadithly/app/core',
               'android/app/src/main/res']:
    assert not git('diff', baseline, '--', prefix), prefix
    preserved[prefix] = True
for path in ['docs/A2_WRAP_UP.md', 'docs/A4_REQUIREMENT_AUDIT.md', 'docs/OPEN_GATES.md',
             'docs/C_NATIVE_REFINEMENTS.md', 'docs/D_WEBSITE_REDESIGN.md']:
    assert Path(path).read_bytes() == git('show', baseline + ':' + path), path
    preserved[path] = digest(Path(path).read_bytes())
assert not any(p.endswith(('.pyc', '.xcresult')) or '__pycache__' in p for p in git('diff', '--cached', '--name-only').decode().splitlines())
results = []
for bundle in args.ios:
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)]))
    assert summary['totalTestCount'] > 0, bundle
    tree = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(bundle)]))
    def cases_in(node):
        if node.get('nodeType') == 'Test Case':
            yield {'name': node['nodeIdentifier'], 'result': node['result']}
        for child in node.get('children', []):
            yield from cases_in(child)
    cases = [case for node in tree['testNodes'] for case in cases_in(node)]
    assert len(cases) == summary['totalTestCount'], bundle
    results.append({'platform': 'ios', 'path': str(bundle), 'summary': summary, 'cases': cases})
for report in args.android:
    root = ET.parse(report).getroot()
    cases = list(root.iter('testcase'))
    assert cases, report
    failures = [{'class': c.get('classname'), 'name': c.get('name'), 'message': c.find('failure').get('message')}
                for c in cases if c.find('failure') is not None]
    results.append({'platform': 'android', 'path': str(report), 'sha256': digest(report.read_bytes()),
                    'tests': len(cases), 'failures': failures,
                    'cases': [{'class': c.get('classname'), 'name': c.get('name'), 'passed': c.find('failure') is None and c.find('skipped') is None} for c in cases]})
report = {'baseline': baseline, 'incoming_working_bytes_preserved': incoming,
          'incoming_files_unstaged': True, 'bounded_source_scope': sorted(changed - set(incoming)),
          'source_sha256': {path: digest(Path(path).read_bytes()) for path in sorted(allowed) if Path(path).is_file()},
          'preserved': preserved, 'historical_plan_and_original_requirements_preserved': True,
          'native_results': results,
          'limits': 'Controlled synthetic page transport on explicitly selected simulator/emulator. No live content, authenticated, physical-device, native-language, full accessibility or release acceptance.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('A5 source preservation and supplied native result readbacks verified.')
