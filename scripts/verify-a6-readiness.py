#!/usr/bin/env python3
"""Verify the local A6 gate inventory, evidence readbacks and preserved worktree."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'docs/verification/a6-readiness'
ALLOWED = {
    'scripts/verify-a6-readiness.py', 'docs/A6_REQUIREMENT_AUDIT.md',
    'docs/A6_GATE_MATRIX.md', 'docs/OPEN_GATES.md', 'docs/PLAN.md',
    'docs/PRODUCT_PROGRAM.md', 'docs/NEXT_SESSION_PROMPT.md',
    'docs/NEXT_SESSION_GOAL.md', 'docs/SESSION_PROMPTS.md',
}


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table(record):
    lines = ['# A6 retained gate matrix', '',
             'October 31, 2026. Local reconciliation only. Every gate below remains open.',
             'Evidence dates describe the underlying record, not a fresh external readback.',
             'Coverage keys in `verification/a6-readiness/gates.json` refer to baseline line numbers.',
             'See [A6 requirement audit](A6_REQUIREMENT_AUDIT.md) for scope and verification.', '']
    area = None
    for gate in record['gates']:
        if gate['area'] != area:
            area = gate['area']
            lines += ['## ' + area, '',
                      '| Gate | Recorded evidence and date | Missing receipt/readback | Owner dependency | Next exact action |',
                      '| --- | --- | --- | --- | --- |']
        evidence = '<br>'.join(
            f"[{Path(e['path']).name}]({e['path'].removeprefix('docs/')}) · {e['as_of']}. {e['detail']}"
            for e in gate['evidence'])
        cells = [gate['id'] + ' ' + gate['gate'], evidence, gate['missing_receipt'],
                 gate['owner_dependency'], gate['next_action']]
        lines.append('| ' + ' | '.join(cell.replace('|', '\\|').replace('\n', ' ') for cell in cells) + ' |')
        # A blank line separates a table from the next section.
        if gate == record['gates'][-1] or record['gates'][record['gates'].index(gate)+1]['area'] != area:
            lines.append('')
    return '\n'.join(lines).rstrip() + '\n'


def test_cases(node):
    if isinstance(node, dict):
        if node.get('nodeType') == 'Test Case':
            yield {'name': node['nodeIdentifier'], 'result': node['result']}
        for value in node.values():
            yield from test_cases(value)
    elif isinstance(node, list):
        for value in node:
            yield from test_cases(value)


def ios_readback(path):
    summary = json.loads(subprocess.check_output([
        'xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', path]))
    tree = json.loads(subprocess.check_output([
        'xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', path]))
    cases = list(test_cases(tree))
    assert len(cases) == summary['totalTestCount'] > 0, path
    return summary, cases


def raw_readbacks():
    a5 = json.loads((ROOT / 'docs/verification/a5-completion/results.json').read_text())
    a4 = json.loads((ROOT / 'docs/verification/a4-localization/final-local-audit.json').read_text())
    results = []
    for item in a5['native_results']:
        path = Path(item['path'])
        assert path.exists(), 'Required historical A5 raw artifact missing: ' + str(path)
        if item['platform'] == 'ios':
            summary, cases = ios_readback(str(path))
            assert cases == item['cases'], str(path)
            results.append({'record': 'A5', 'path': str(path), 'cases': len(cases),
                            'passed': summary['passedTests'], 'failed': summary['failedTests'],
                            'scope': 'Historical per-case outcomes unchanged, including rejected attempts'})
        else:
            assert digest(path) == item['sha256'], str(path)
            cases = list(ET.parse(path).getroot().iter('testcase'))
            assert len(cases) == item['tests'], str(path)
            results.append({'record': 'A5', 'path': str(path), 'sha256': digest(path),
                            'cases': len(cases), 'scope': 'Historical XML bytes unchanged'})
    for item in a4['native_results']:
        path = Path(item['path'])
        assert path.exists(), 'Required historical A4 raw artifact missing: ' + str(path)
        if path.suffix == '.xcresult':
            summary, cases = ios_readback(str(path))
            if item['scope'] == 'Entire bundle':
                selected = cases
                assert summary['result'] == 'Passed', str(path)
            else:
                scope = item['scope']
                selected = [c for c in cases if c['name'] in scope.get('cases', []) or
                            any(c['name'].startswith(p) for p in scope.get('prefixes', []))]
                assert all(any(c['name'] == name for c in selected) for name in scope.get('cases', [])), str(path)
            assert len(selected) == item['passed'] > 0 and all(c['result'] == 'Passed' for c in selected), str(path)
            results.append({'record': 'A4', 'path': str(path), 'selected_passed': len(selected),
                            'overall_bundle_result': summary['result'], 'scope': item['scope']})
        else:
            assert digest(path) == item['sha256'], str(path)
            results.append({'record': 'A4', 'path': str(path), 'sha256': digest(path),
                            'scope': 'Historical selected XML bytes unchanged'})
    return results


def verify(record, raw):
    baseline = json.loads((DIRECTORY / 'baseline.json').read_text())
    ids = {gate['id'] for gate in record['gates']}
    assert len(ids) == len(record['gates']) == 41
    required = ['id', 'area', 'gate', 'status', 'evidence', 'missing_receipt', 'owner_dependency', 'next_action']
    for gate in record['gates']:
        assert all(gate.get(field) for field in required), gate['id']
        assert gate['status'] == 'retained_open', gate['id']
        for evidence in gate['evidence']:
            assert all(evidence.get(key) for key in ['path', 'as_of', 'detail']), gate['id']
            assert (ROOT / evidence['path']).is_file(), evidence['path']
    coverage = record['baseline_gate_coverage']
    assert set(coverage) == {entry['key'] for entry in baseline['gate_inventory']}
    assert all(mapped and set(mapped) <= ids for mapped in coverage.values())
    for entry in baseline['gate_inventory']:
        source, line = entry['key'].rsplit(':', 1)
        original = git('show', baseline['baseline'] + ':docs/' + source).decode().splitlines()[int(line)-1]
        assert original == entry['text'], entry['key']
        current = (ROOT / 'docs' / source).read_text()
        expected = entry['text'].replace('- [ ] A6.', '- [x] A6.')
        assert expected in current, 'Gate removed/closed without authority: ' + entry['key']
    assert (ROOT / 'docs/A6_GATE_MATRIX.md').read_text() == table(record)
    for path, expected in baseline['incoming'].items():
        assert digest(ROOT / path) == expected['working_sha256'], 'Incoming bytes changed: ' + path
        assert git('rev-parse', ':'+path).decode().strip() == expected['index_blob'], 'Incoming staged: '+path
    changed = set(git('diff', '--name-only', baseline['baseline']).decode().splitlines())
    untracked = set(git('ls-files', '--others', '--exclude-standard').decode().splitlines())
    incoming = set(baseline['incoming'])
    def allowed(path):
        return path in ALLOWED or path.startswith('docs/verification/a6-readiness/')
    assert all(allowed(p) for p in changed-incoming), sorted(changed-incoming-ALLOWED)
    assert all(allowed(p) or p in baseline['initial_untracked'] or p.startswith('scripts/__pycache__/') for p in untracked)
    for path, marker in [('docs/PLAN.md', '## Owner continuation order, October 31'),
                         ('docs/PRODUCT_PROGRAM.md', '## Owner order, October 26'),
                         ('docs/OPEN_GATES.md', 'Updated 2026-10-26'),
                         ('docs/SESSION_PROMPTS.md', '## D0: restore browser control'),
                         ('docs/NEXT_SESSION_GOAL.md', '## A4 evidence-intake checkpoint, October 30')]:
        original = git('show', baseline['baseline'] + ':' + path).decode()
        current = (ROOT / path).read_text().replace('- [x] A6.', '- [ ] A6.')
        assert original[original.index(marker):] == current[current.index(marker):], path
    evidence = {}
    for path, old_sha in baseline['evidence_sha256'].items():
        current_sha = digest(ROOT / path)
        if path not in ALLOWED:
            assert current_sha == old_sha, 'Historical evidence changed: ' + path
        evidence[path] = {'sha256': current_sha, 'unchanged_since_start': current_sha == old_sha}
    a5 = json.loads((ROOT / 'docs/verification/a5-completion/results.json').read_text())
    product_hashes = {p: digest(ROOT / p) for p in a5['source_sha256'] if p.startswith(('ios/', 'android/'))}
    assert all(value == a5['source_sha256'][path] for path, value in product_hashes.items()), 'A5 source differs'
    staged = git('diff', '--cached', '--name-only').decode().splitlines()
    assert all(allowed(p) for p in staged), staged
    assert not any('__pycache__' in p or p.endswith(('.pyc', '.xcresult')) for p in staged)
    prompt = (ROOT / 'docs/NEXT_SESSION_PROMPT.md').read_text()
    for term in ['A7', 'A1/A3', 'A4', 'row mode off', 'B/C/D', 'Linear', 'final', 'POST_GOAL_BACKLOG',
                 'GPT-only', 'no Relay', 'action-time approval', 'G01', 'G41']:
        assert term in prompt, 'Missing handoff preservation: ' + term
    return {'date': '2026-10-31', 'baseline': baseline['baseline'], 'gate_groups': len(ids),
            'mapped_baseline_entries': len(coverage), 'external_gates_closed': 0,
            'incoming_working_bytes_and_index_preserved': baseline['incoming'],
            'changed_scoped_paths': sorted(changed-incoming), 'staged_scoped_paths': staged,
            'evidence_records': evidence, 'a5_product_source_sha256': product_hashes,
            'historical_requirements_preserved_except_authorized_A6_checkbox': True,
            'native_artifact_readbacks': raw_readbacks() if raw else [],
            'limits': 'Fresh local gate/source checks and re-read historical artifacts only. No new native run, live/authenticated/physical/provider/store/policy/backup/account readback or acceptance.'}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--render', action='store_true', help='Render the matrix from gates.json')
parser.add_argument('--raw-native', action='store_true', help='Re-read existing A4/A5 raw native artifacts, without running apps')
parser.add_argument('--output', type=Path, help='Write the verification report')
args = parser.parse_args()
record = json.loads((DIRECTORY / 'gates.json').read_text())
if args.render:
    (ROOT / 'docs/A6_GATE_MATRIX.md').write_text(table(record))
if args.output:
    result = verify(record, args.raw_native)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"A6: {result['gate_groups']} retained-open groups; {result['mapped_baseline_entries']} mapped entries; incoming bytes/index and A5 sources preserved; {len(result['native_artifact_readbacks'])} historical raw artifacts re-read; zero external gates closed.")
assert args.render or args.output, 'Select --render and/or --output'
