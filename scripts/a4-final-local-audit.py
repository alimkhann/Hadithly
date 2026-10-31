#!/usr/bin/env python3
"""Read A4 source/resource evidence without granting language or release approval."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import localization_audit as audit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--native', action='store_true', help='Re-read completed raw native result artifacts')
args = parser.parse_args()
sha = lambda data: hashlib.sha256(data).hexdigest()
review = json.loads(Path('docs/a4-runtime-dispositions.json').read_text())
assert review['locales'] == list(audit.WAVE1)
for contract in review['source_contracts']:
    text = Path(contract['path']).read_text()
    for fragment in contract['required']:
        assert fragment in text, (contract['path'], fragment)
counts_ios, drafts_ios, failures_ios, _ = audit.audit_ios(True)
counts_android, identical, failures_android, _ = audit.audit_android(True)
assert not failures_ios and not failures_android, failures_ios + failures_android
report_path = args.output.parent / 'runtime-candidates.json'
audit.write_runtime_report(report_path)
report = json.loads(report_path.read_text())
assert not any(row['category'].startswith('missing-') for row in report['candidates'])
remaining = [row for row in report['candidates'] if row['category'] in ['dynamic-review', 'direct-literal-review', 'example-or-symbol-review']]
identity = lambda row: (row['platform'], row['file'], row['call'], row['value'], row['category'])
assert {identity(row) for row in remaining} == {identity(row) for row in review['lexical_dispositions']}, 'Review the changed lexical candidate set'
assert all(row['disposition'] for row in review['lexical_dispositions'])
# Every translatable XML resource contributes to the review ledger, including native.xml.
ledger = [line.split('\t') for line in audit.LEDGER.read_text().splitlines()[1:]]
for platform, count in [('ios', counts_ios), ('android', counts_android)]:
    for locale in audit.WAVE1:
        rows = [row for row in ledger if row[:2] == [platform, locale]]
        assert sum(int(row[3]) for row in rows) == count
        assert all(row[5:] == ['unassigned', 'pending exact-copy review'] for row in rows)
identical_rows = []
for path in sorted((audit.ANDROID_RES / 'values').glob('*.xml')):
    strings, _ = audit.android_nodes(path)
    strings = {key: node for key, node in strings.items() if node.attrib.get('translatable') != 'false'}
    if not strings: continue
    for locale in audit.WAVE1[1:]:
        target, _ = audit.android_nodes(audit.ANDROID_RES / audit.android_qualifier(locale) / path.name)
        for key, node in strings.items():
            if key in target and target[key].text == node.text:
                identical_rows.append({'locale': locale, 'file': path.name, 'resource': key, 'value': node.text,
                                       'status': 'Identical candidate; units, loanwords, greetings and grade transliterations require exact-copy review.'})
# These original records and core data/control-plane paths retain their initial bytes.
baseline = review['baseline']
for path in review['unchanged_paths']:
    assert Path(path).exists(), path
    subprocess.run(['git', 'diff', '--exit-code', baseline, '--', path], check=True, stdout=subprocess.DEVNULL)
original_plan = subprocess.check_output(['git', 'show', baseline + ':docs/PLAN.md']).decode()
marker = '## A4 Settings profile notices, October 31'
assert Path('docs/PLAN.md').read_text().split(marker, 1)[1] == original_plan.split(marker, 1)[1]
original_program = subprocess.check_output(['git', 'show', baseline + ':docs/PRODUCT_PROGRAM.md']).decode()
marker = '## Owner order, October 26'
assert Path('docs/PRODUCT_PROGRAM.md').read_text().split(marker, 1)[1] == original_program.split(marker, 1)[1]
native = []
if args.native:
    for item in review['ios_final_bundles']:
        bundle = item if isinstance(item, str) else item['path']
        result = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', bundle]))
        if isinstance(item, str):
            assert result['result'] == 'Passed' and result['failedTests'] == 0, bundle
            native.append({'path': bundle, 'passed': result['passedTests'], 'failed': result['failedTests'], 'scope': 'Entire bundle'})
        else:
            tree = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', bundle]))
            cases = []
            def visit(node):
                if isinstance(node, dict):
                    if node.get('nodeType') == 'Test Case': cases.append(node)
                    for value in node.values(): visit(value)
                elif isinstance(node, list):
                    for value in node: visit(value)
            visit(tree)
            selected = [case for case in cases if case['nodeIdentifier'] in item.get('cases', []) or any(case['nodeIdentifier'].startswith(prefix) for prefix in item.get('prefixes', []))]
            assert selected and all(case['result'] == 'Passed' for case in selected), item
            assert all(any(case['nodeIdentifier'] == name for case in selected) for name in item.get('cases', [])), item
            native.append({'path': bundle, 'overall_bundle_result': result['result'], 'scope': item, 'passed': len(selected), 'failed': 0})
    for item in review['android_final_reports']:
        path = Path(item['path'])
        cases = list(ET.parse(path).getroot().iter('testcase'))
        selected = [case for case in cases if case.attrib['name'] in item['cases']] if item['cases'] else cases
        assert selected and (not item['cases'] or len(selected) == len(item['cases'])), item
        assert all(case.find('failure') is None and case.find('error') is None and case.find('skipped') is None for case in selected), item
        native.append({'path': str(path), 'sha256': sha(path.read_bytes()), 'passed': len(selected), 'failed': 0})
for directory in ['ios/Hadithly/Features', 'android/app/src/main/kotlin/com/hadithly/app/features']:
    assert not any('authenticity.displayLabel' in path.read_text() for path in Path(directory).rglob('*') if path.suffix in ['.swift', '.kt'])
source_files = []
for directory, extension in [('ios/Hadithly', '*.swift'), ('android/app/src/main/kotlin', '*.kt')]:
    for path in sorted(Path(directory).rglob(extension)):
        source_files.append({'path': str(path), 'sha256': sha(path.read_bytes())})
result = {'date': '2026-10-31', 'scope': 'Current native UI source inventory, all native catalog/XML resources and the finite repaired A4 presentations.',
          'ios_keys': counts_ios, 'ios_needs_review_localizations': drafts_ios,
          'ios_needs_review_units': sum(int(row[4]) for row in ledger if row[0] == 'ios'), 'android_resources': counts_android,
          'resource_failures': [], 'android_english_identical_candidates': identical, 'identical_candidate_details': identical_rows,
          'lexical_counts': report['counts'], 'lexical_dispositions': review['lexical_dispositions'],
          'supplementary_source_review': review['source_review'], 'source_files': source_files,
          'native_raw_readback_requested': args.native, 'native_results': native,
          'acceptance': {'locally_verifiable_checklist': 'Complete locally; final native artifacts re-read' if args.native else 'Source-only audit; native artifacts not re-read',
                         'full_A4': 'OPEN', 'exact_copy_native_speaker_review': 'OPEN', 'full_accessibility_and_physical_authenticated_journeys': 'OPEN'},
          'preserved_program': 'A2 wrap-up, B/C/D local completion, original checklist and historical gates remain unchanged.',
          'limitations': 'A source inventory and controlled rendering do not prove real account, content, purchase, notification, physical-device, language, or release acceptance.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(f'A4 source/resource audit: {counts_ios} iOS keys, {counts_android} Android resources, 0 structural failures; {len(native)} native artifact readbacks. Full A4 remains OPEN.')
