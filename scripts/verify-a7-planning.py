#!/usr/bin/env python3
"""Check the A7 local planning scope without contacting services or devices."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'docs/verification/a7-planning'
NEW = {
    'scripts/verify-a7-planning.py', 'docs/A7_MEASUREMENT_PLAN.md',
    'docs/A7_READER_SESSION_PROTOCOL.md', 'docs/A7_GATE_CARRY_FORWARD.md',
    'docs/A7_REQUIREMENT_AUDIT.md',
}


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode()


def digest(path):
    content = ('symlink:' + os.readlink(path)).encode() if path.is_symlink() else path.read_bytes()
    return hashlib.sha256(content).hexdigest()


def carried_gates(record):
    lines = ['# A7 carried gates', '',
             'October 31, 2026. All G01-G41 remain OPEN. Retention is not acceptance.',
             'This table carries the complete A6 evidence, missing receipts, dependencies and actions.',
             'Dates below belong to the underlying records, not new account or device readbacks.',
             'The only new G38 evidence is the local measurement plan and draft session protocol.',
             'Actual consented observation and conversion evidence remain unavailable.',
             'A6 historical wording is retained; the G38 action below advances to preparation for approval.',
             'Source: [A6 matrix](A6_GATE_MATRIX.md) and its unchanged structured inventory.',
             'Regenerate with `python3 scripts/verify-a7-planning.py --render-gates`.', '']
    for gate in record['gates']:
        lines += ['## ' + gate['id'] + ' ' + gate['gate'], '', 'Status: OPEN, retained.', '']
        for evidence in gate['evidence']:
            lines += [f"Recorded evidence: [{Path(evidence['path']).name}]({evidence['path'].removeprefix('docs/')})",
                      f"as of {evidence['as_of']}. {evidence['detail']}", '']
        lines += ['Missing receipt/readback: ' + gate['missing_receipt'], '',
                  'Owner dependency: ' + gate['owner_dependency'], '']
        action = gate['next_action']
        if gate['id'] == 'G38':
            lines += ['New local evidence, 2026-10-31: [measurement plan](A7_MEASUREMENT_PLAN.md),',
                      '[draft protocol](A7_READER_SESSION_PROTOCOL.md) and [audit](A7_REQUIREMENT_AUDIT.md).',
                      'The plan/protocol portion of the A6 missing list is now supplied locally.',
                      'Planning only. No consent, participant, observation, payment or production receipt exists.', '']
            action = ('Prepare one private-study readiness and approval packet with exact invitation, '
                      'audience, facilitator, safe content/build/device, collection-off readback plan, '
                      'storage/deletion dates and proposed calendar. Keep contact, accounts, sessions '
                      'and activation unstarted until their specific approval. Then conduct only the '
                      'approved consented study and reconcile actual evidence; A7 stays unchecked.')
        lines += ['Next exact action: ' + action, '']
    return '\n'.join(lines).rstrip() + '\n'


def verify():
    baseline = json.loads((DIRECTORY / 'baseline.json').read_text())
    record = json.loads((ROOT / 'docs/verification/a6-readiness/gates.json').read_text())
    assert [g['id'] for g in record['gates']] == [f'G{i:02}' for i in range(1, 42)]
    assert all(g['status'] == 'retained_open' for g in record['gates'])
    assert len(record['baseline_gate_coverage']) == 74
    assert (ROOT / 'docs/A7_GATE_CARRY_FORWARD.md').read_text() == carried_gates(record)
    for path, expected in baseline['immutable_sha256'].items():
        assert digest(ROOT / path) == expected, 'Preserved input changed: ' + path
    for path, expected in baseline['incoming'].items():
        assert digest(ROOT / path) == expected['working_sha256'], path
        assert git('rev-parse', ':' + path).strip() == expected['index_blob'], 'Incoming index changed: ' + path

    allowed = set(baseline['mutable_existing']) | NEW
    def permitted(path):
        return path in allowed or path.startswith('docs/verification/a7-planning/')
    changed = set(git('diff', '--name-only', baseline['baseline_commit']).splitlines())
    untracked = set(git('ls-files', '--others', '--exclude-standard').splitlines())
    assert all(permitted(p) for p in changed - set(baseline['incoming'])), sorted(changed)
    assert all(permitted(p) or p in baseline['initial_untracked'] for p in untracked), sorted(untracked)
    staged = git('diff', '--cached', '--name-only').splitlines()
    assert all(permitted(p) for p in staged), staged

    markers = {
        'docs/PLAN.md': '## A6 local readiness audit, October 31',
        'docs/PRODUCT_PROGRAM.md': '## Owner order, October 26',
        'docs/OPEN_GATES.md': '## A6 reconciliation, October 31',
        'docs/SESSION_PROMPTS.md': '## D0: restore browser control',
        'docs/NEXT_SESSION_GOAL.md': '## A4 evidence-intake checkpoint, October 30',
    }
    for path, marker in markers.items():
        original = git('show', baseline['baseline_commit'] + ':' + path)
        current = (ROOT / path).read_text()
        assert original[original.index(marker):] == current[current.index(marker):], 'History changed: ' + path
    program = (ROOT / 'docs/PRODUCT_PROGRAM.md').read_text()
    original_program = git('show', baseline['baseline_commit'] + ':docs/PRODUCT_PROGRAM.md')
    assert re.findall(r'^\s*- \[[ x]\].*', program, re.M) == re.findall(r'^\s*- \[[ x]\].*', original_program, re.M)
    assert '- [ ] A7.' in program and '- [x] A7.' not in program
    old_trail = git('show', baseline['baseline_commit'] + ':docs/product-program/decisions.tsv')
    assert (ROOT / 'docs/product-program/decisions.tsv').read_text().startswith(old_trail)

    plan = (ROOT / 'docs/A7_MEASUREMENT_PLAN.md').read_text()
    rows = [line.split('|')[1:-1] for line in plan.splitlines() if re.match(r'\| M\d\d ', line)]
    assert len(rows) == 14 and all(len(row) == 8 and all(cell.strip() for cell in row) for row in rows)
    assert [row[0].strip().split()[0] for row in rows] == [f'M{i:02}' for i in range(1, 15)]
    catalog = json.loads((ROOT / 'docs/analytics-catalog.json').read_text())
    metrics = {family + '.' + variant for family, variants in catalog['families'].items() for variant in variants}
    used = set(re.findall(r'`((?:onboarding_step|reader_open_result|restoration_result|paywall_result)\.[a-z_]+)`', plan))
    assert used and used <= metrics, used - metrics
    protocol = (ROOT / 'docs/A7_READER_SESSION_PROTOCOL.md').read_text()
    for term in ['NOT STARTED', 'NOT APPROVED', 'D1', 'D7', 'D14', 'Day 28', 'withdrawal',
                 'no to follow-up', 'prompted', 'unknown', 'collection off', 'No silent fallback']:
        assert term in protocol, 'Missing protocol boundary: ' + term
    prompt = (ROOT / 'docs/NEXT_SESSION_PROMPT.md').read_text()
    for term in ['A7', 'G01', 'G41', 'A1/A3', 'A4', 'row mode off', 'B/C/D', 'Linear',
                 'final', 'POST_GOAL_BACKLOG', 'GPT-only', 'no Relay', 'action-time approval',
                 'Do not recruit', 'observation', 'unchecked']:
        assert term in prompt, term

    docs = sorted(NEW - {'scripts/verify-a7-planning.py'} | set(baseline['mutable_existing']) - {'docs/product-program/decisions.tsv'})
    links = 0
    for path in docs:
        for target in re.findall(r'\]\(([^)]+)\)', (ROOT / path).read_text()):
            if '://' in target or target.startswith('#'):
                continue
            assert (ROOT / path).parent.joinpath(target.split('#')[0]).exists(), (path, target)
            links += 1
    for path in staged:
        assert not any(part in path for part in ['__pycache__', '.xcresult', '.pyc', '.env.local', 'Secrets.xcconfig', 'secrets.properties'])
        content = subprocess.check_output(['git', '-C', str(ROOT), 'show', ':' + path]).decode('utf-8')
        assert not re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bsk-[A-Za-z0-9]{20,}', content), path
        assert not re.search(r'(?im)^\s*(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[\"\x27]?[A-Za-z0-9_/-]{16,}', content), path
    readbacks = json.loads((DIRECTORY / 'historical-readbacks.json').read_text())
    assert len(readbacks['native_artifact_readbacks']) == 37
    return {
        'date': '2026-10-31', 'baseline_commit': baseline['baseline_commit'],
        'preserved_tracked_files': len(baseline['immutable_sha256']),
        'incoming_paths_preserved_and_unstaged': list(baseline['incoming']),
        'gate_groups_retained_open': 41, 'baseline_gate_entries': 74, 'external_gates_closed': 0,
        'metric_rows_with_all_eight_fields': len(rows), 'existing_metric_names_checked': sorted(used),
        'original_program_checkboxes_unchanged': True, 'historical_sections_preserved': True,
        'historical_native_artifacts_read_before_edits': 37, 'local_links_checked': links,
        'staged_scoped_paths': staged, 'staged_utf8_secret_artifact_scan': 'passed' if staged else 'not staged yet',
        'limits': 'Local documentation/source checks and historical artifact readback only. No new native run, participant, account, vendor, store, production or acceptance evidence.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render-gates', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.render_gates:
        record = json.loads((ROOT / 'docs/verification/a6-readiness/gates.json').read_text())
        (ROOT / 'docs/A7_GATE_CARRY_FORWARD.md').write_text(carried_gates(record))
    if args.output:
        result = verify()
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        print(f"A7 planning: {result['metric_rows_with_all_eight_fields']} complete metric rows; 41 OPEN gate groups; "
              f"{result['preserved_tracked_files']} tracked inputs preserved; zero external gates closed.")
    assert args.output or args.render_gates, 'Select --render-gates and/or --output'


if __name__ == '__main__':
    main()
