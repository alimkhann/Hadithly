#!/usr/bin/env python3
"""Record native test results, retaining rerun history and each case's latest result."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ios-result', action='append', default=[], type=Path)
parser.add_argument('--android-unit-dir', type=Path)
parser.add_argument('--android-ui-dir', type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--require-green', action='store_true')
args = parser.parse_args()
report = {'ios': {'runs': [], 'latestCases': {}}, 'android': {}}
runs = []
for path in args.ios_result:
    def read(kind):
        return json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(path)], text=True))
    runs.append((read('summary'), read('tests'), path))
for summary, tree, path in sorted(runs, key=lambda item: item[0]['startTime']):
    report['ios']['runs'].append({'bundle': path.name, **{key: summary.get(key) for key in ['startTime', 'result', 'passedTests', 'failedTests', 'skippedTests']}})
    def visit(node, bundle=''):
        if 'test bundle' in node.get('nodeType', '').lower():
            bundle = node['name']
        if node.get('nodeType') == 'Test Case':
            identifier = bundle + '/' + node['nodeIdentifier']
            report['ios']['latestCases'][identifier] = {'result': node['result'], 'bundle': path.name}
        for child in node.get('children', []):
            visit(child, bundle)
    for node in tree['testNodes']:
        visit(node)
report['ios']['latestCounts'] = dict(Counter(case['result'] for case in report['ios']['latestCases'].values()))
for name, directory in [('unit', args.android_unit_dir), ('ui', args.android_ui_dir)]:
    if directory is None:
        continue
    cases, files = {}, []
    for path in sorted(directory.glob('TEST*.xml')):
        raw = path.read_bytes()
        files.append({'file': path.name, 'sha256': hashlib.sha256(raw).hexdigest()})
        for case in ET.fromstring(raw).iter('testcase'):
            result = 'Failed' if case.find('failure') is not None or case.find('error') is not None else 'Skipped' if case.find('skipped') is not None else 'Passed'
            cases[case.get('classname', '') + '/' + case.attrib['name']] = result
    if not cases:
        raise SystemExit(f'No test cases found in {directory}')
    report['android'][name] = {'counts': dict(Counter(cases.values())), 'cases': cases, 'reports': files}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
counts = {'ios': report['ios']['latestCounts'], **{'android_' + key: value['counts'] for key, value in report['android'].items()}}
print(json.dumps(counts))
if args.require_green and any(count.get('Failed', 0) > 0 for count in counts.values()):
    raise SystemExit('Latest native test results contain failures')
