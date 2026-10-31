#!/usr/bin/env python3
"""Verify the local A7 readiness packet without accessing services or devices."""
import argparse
from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'docs/verification/a7-readiness'
NEW = {'docs/A7_OBSERVATION_READINESS.md', 'docs/A7_READINESS_AUDIT.md',
       'scripts/verify-a7-readiness.py'}


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).decode()


def digest(path):
    data = ('symlink:' + os.readlink(path)).encode() if path.is_symlink() else path.read_bytes()
    return hashlib.sha256(data).hexdigest()


def quoted(text, start, end):
    section = text.split(start, 1)[1].split(end, 1)[0]
    return '\n'.join(line for line in section.splitlines() if line.startswith('>')) + '\n'


def verify():
    baseline = json.loads((DIRECTORY / 'baseline.json').read_text())
    proposal = json.loads((DIRECTORY / 'proposal.json').read_text())
    inventory = json.loads((ROOT / 'docs/verification/a6-readiness/gates.json').read_text())
    for path, expected in baseline['immutable_sha256'].items():
        assert digest(ROOT / path) == expected, 'Frozen input changed: ' + path
    for path, expected in baseline['incoming'].items():
        assert digest(ROOT / path) == expected['working_sha256'], path
        assert git('rev-parse', ':' + path).strip() == expected['index_blob'], path
    assert proposal['retained_gates'] == inventory['gates'], 'Historical gates changed'
    assert [g['id'] for g in inventory['gates']] == [f'G{i:02}' for i in range(1, 42)]
    assert all(g['status'] == 'retained_open' for g in inventory['gates'])
    assert len(inventory['baseline_gate_coverage']) == 74
    for key in ['status', 'study_status', 'contact_approval', 'observation_approval',
                'consent_review_status']:
        assert proposal[key] in ['NOT APPROVED', 'NOT STARTED', 'PENDING'], key
    assert all(proposal[key] == 0 for key in ['participants_enrolled', 'sessions_observed',
                                            'contacts_made', 'max_new_spend'])
    assert proposal['participant_min'] == 6 and proposal['participant_max'] == 8
    assert proposal['minimum_per_platform'] == 3 and proposal['language'] == 'en'
    assert proposal['max_initial_invitations'] == proposal['max_optional_followup_invitations'] == 8
    assert len(proposal['owner_choices_pending']) == 9
    day0 = datetime.fromisoformat(proposal['batch_day0'])
    close = datetime.fromisoformat(proposal['observation_close'])
    deletion = datetime.fromisoformat(proposal['notes_delete_by'])
    assert close.date() == (day0 + timedelta(days=21)).date()
    assert deletion.date() == (day0 + timedelta(days=28)).date()
    assert proposal['contact_delete_by'] == proposal['observation_close']
    assert len(proposal['slots']) == 8
    assert len({s['baseline_start'] for s in proposal['slots']}) == 8
    for slot in proposal['slots']:
        start = datetime.fromisoformat(slot['baseline_start'])
        latest = datetime.fromisoformat(slot['latest_first_render'])
        assert 0 <= (start.date() - day0.date()).days <= 2
        assert latest - start == timedelta(minutes=30)
        for key, hours in [('D1_latest_end', 48), ('D7_latest_end', 192), ('D14_latest_end', 360)]:
            assert datetime.fromisoformat(slot[key]) == latest + timedelta(hours=hours)
        followup = datetime.fromisoformat(slot['followup_capacity'])
        assert followup >= datetime.fromisoformat(slot['D14_latest_end'])
        assert followup + timedelta(minutes=15) < close
        assert slot['assigned'] is False
    packet = (ROOT / 'docs/A7_OBSERVATION_READINESS.md').read_text()
    for field, start, end in [
        ('consent_draft_sha256', '## Proposed consent handout', 'Keep consent choices separate'),
        ('invitation_sha256', 'INV-A7-R1-en, proposed spoken invitation after approval:', 'FUP-A7-R1-en'),
    ]:
        assert hashlib.sha256(quoted(packet, start, end).encode()).hexdigest() == proposal[field], field
    for term in ['NOT APPROVED', 'NOT STARTED', 'Language review is PENDING',
                 'enabled=false', 'crash reports', 'zero analytics/crash', 'unknown',
                 'G01-G41', 'G39', 'G40', 'row mode off', 'no Relay', 'GPT-only']:
        assert term in packet, term
    audit = (ROOT / 'docs/A7_READINESS_AUDIT.md').read_text()
    assert re.findall(r'^\| (G\d\d) ', audit, re.M) == [f'G{i:02}' for i in range(1, 42)]
    markers = {'docs/PLAN.md': '## A7 local planning checkpoint, October 31',
               'docs/PRODUCT_PROGRAM.md': '## Owner order, October 26',
               'docs/OPEN_GATES.md': '## A7 planning reconciliation, October 31',
               'docs/SESSION_PROMPTS.md': '## D0: restore browser control',
               'docs/NEXT_SESSION_GOAL.md': '## A4 evidence-intake checkpoint, October 30'}
    for path, marker in markers.items():
        original = git('show', baseline['baseline_commit'] + ':' + path)
        current = (ROOT / path).read_text()
        assert original[original.index(marker):] == current[current.index(marker):], path
    original_program = git('show', baseline['baseline_commit'] + ':docs/PRODUCT_PROGRAM.md')
    program = (ROOT / 'docs/PRODUCT_PROGRAM.md').read_text()
    assert re.findall(r'^\s*- \[[ x]\].*', program, re.M) == re.findall(r'^\s*- \[[ x]\].*', original_program, re.M)
    assert '- [ ] A7.' in program and '- [x] A7.' not in program
    old_trail = git('show', baseline['baseline_commit'] + ':docs/product-program/decisions.tsv')
    assert (ROOT / 'docs/product-program/decisions.tsv').read_text().startswith(old_trail)
    allowed = set(baseline['mutable_existing']) | NEW

    def permitted(path):
        return path in allowed or path.startswith('docs/verification/a7-readiness/')

    changed = set(git('diff', '--name-only', baseline['baseline_commit']).splitlines())
    untracked = set(git('ls-files', '--others', '--exclude-standard').splitlines())
    assert all(permitted(p) for p in changed - set(baseline['incoming'])), sorted(changed)
    assert all(permitted(p) or p in baseline['initial_untracked'] for p in untracked), sorted(untracked)
    staged = git('diff', '--cached', '--name-only').splitlines()
    assert all(permitted(p) for p in staged), staged
    links = 0
    for path in sorted((allowed - {'scripts/verify-a7-readiness.py', 'docs/product-program/decisions.tsv'})):
        for target in re.findall(r'\]\(([^)]+)\)', (ROOT / path).read_text()):
            if '://' in target or target.startswith('#'):
                continue
            assert (ROOT / path).parent.joinpath(target.split('#')[0]).exists(), (path, target)
            links += 1
    for path in staged:
        assert not any(t in path for t in ['__pycache__', '.pyc', '.xcresult', '.env.local', 'Secrets.xcconfig', 'secrets.properties'])
        content = git('show', ':' + path)
        assert not re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bsk-[A-Za-z0-9]{20,}', content), path
        assert not re.search(r'(?im)^\s*(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[\"\x27]?[A-Za-z0-9_/-]{16,}', content), path
        assert (ROOT / path).read_text() == content, 'Staged/working mismatch: ' + path
    return {'date': '2026-10-31', 'baseline_commit': baseline['baseline_commit'],
            'immutable_tracked_paths_preserved': len(baseline['immutable_sha256']),
            'incoming_working_and_index_paths_preserved': list(baseline['incoming']),
            'retained_open_gates': 41, 'baseline_gate_entries': 74, 'external_gates_closed': 0,
            'calendar_capacity_slots_checked': 8, 'latest_D14_precedes_each_followup': True,
            'day21_close_and_day28_deletion_checked': True,
            'original_checkboxes_history_and_blank_templates_preserved': True,
            'consent_review_and_action_approval_pending': True, 'local_links_checked': links,
            'staged_paths': staged,
            'limits': 'Local packet/source/calendar checks only. No native run, participant, contact, language approval, encryption drill, current service readback or release acceptance.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = verify()
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"A7 readiness: {result['immutable_tracked_paths_preserved']} frozen inputs, 41 OPEN gates, eight dated capacity slots; no external gates closed.")
