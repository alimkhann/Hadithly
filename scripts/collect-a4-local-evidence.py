#!/usr/bin/env python3
"""Collect native result readbacks and original captures for a bounded A4 unit."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--unit', required=True)
parser.add_argument('--work-dir', type=Path, required=True)
parser.add_argument('--source', required=True)
parser.add_argument('--ios', action='append', default=[], help='Completed xcresult bundle')
parser.add_argument('--android', action='append', default=[], help='Preserved result XML directory')
parser.add_argument('--capture-prefix', required=True)
args = parser.parse_args()
output = Path('docs/verification/a4-localization')
captures = output / args.unit
captures.mkdir(parents=True, exist_ok=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
runs = []
for bundle in args.ios:
    summary = json.loads(subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', bundle]))
    runs.append({'bundle': bundle, **{k: summary[k] for k in ['result', 'passedTests', 'failedTests', 'skippedTests', 'startTime', 'finishTime']}})
android = []
for directory in args.android:
    for path in sorted(Path(directory).rglob('TEST-*.xml')):
        root = ET.parse(path).getroot()
        android.append({'file': str(path), 'sha256': sha(path), 'cases': [
            {'class': c.attrib.get('classname'), 'name': c.attrib['name'],
             'result': 'Failed' if c.find('failure') is not None or c.find('error') is not None else 'Skipped' if c.find('skipped') is not None else 'Passed'}
            for c in root.iter('testcase')]})
manifest = []
selected = {'en-1', 'ar-1', 'ur-1', 'ar-large-1', 'ur-large-1', 'ru-large-1', 'bn-large-1', 'bn-large-18', 'ar-large-18'}
for directory in sorted(args.work_dir.glob(args.capture_prefix + '*ios-captures')):
    source_manifest = directory / 'manifest.json'
    if not source_manifest.exists(): continue
    for block in json.loads(source_manifest.read_text()):
        for attachment in block['attachments']:
            name = attachment['suggestedHumanReadableName'].split('_0_')[0]
            if not name.startswith(args.capture_prefix): continue
            path = directory / attachment['exportedFileName']
            target = captures / ('ios-' + name + '.png')
            keep = 'before' in name or name.removeprefix(args.capture_prefix + '-') in selected
            if keep: shutil.copy(path, target)
            manifest.append({'platform': 'ios', 'name': name, 'original': str(path), 'sha256': sha(path), 'committed': str(target) if keep else None})
for path in sorted((args.work_dir / 'android-captures').glob('finishing-' + args.capture_prefix + '*.png')):
    name = path.stem.removeprefix('finishing-')
    target = captures / ('android-' + name + '.png')
    keep = 'before' in name or name.removeprefix(args.capture_prefix + '-') in selected
    if keep: shutil.copy(path, target)
    manifest.append({'platform': 'android', 'name': name, 'original': str(path), 'sha256': sha(path), 'committed': str(target) if keep else None})
(captures / 'capture-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
copy = json.loads(Path(args.source).read_text())
report = {'date': '2026-10-31', 'scope': 'Controlled local rendering and synthetic store/callback evidence only.',
          'native_review': 'pending', 'source': args.source, 'locales': list(copy['locales']), 'copy_key_count': len(copy['keys']),
          'ios': runs, 'android': android, 'capture_count': len(manifest), 'selected_original_captures': sum(bool(c['committed']) for c in manifest),
          'raw_evidence': str(args.work_dir), 'log_hashes': {p.name: sha(p) for p in args.work_dir.glob('*.log')},
          'device_limits': {'ios': 'D47D7363-4705-4767-8617-F47DDB6A3241, iOS 27 simulator, LA2Verification debug, light; Accessibility XXXL ar/ur/ru/bn',
                            'android': 'Guarded emulator-5554, Android 16 debug, light; controlled fontScale 2.0 ar/ur/ru/bn'},
          'open_gates': ['Exact-copy native-speaker approval', 'Full accessibility and actual authenticated/physical-device journeys',
                         'A1/A3', 'A5-A7/readiness', 'E and final original-objective audit',
                         'Existing content, store/purchase, actual annual billing total, production, backup/recovery, publication and LA4 gates']}
(output / (args.unit + '.json')).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f'{args.unit}: {len(runs)} iOS result readbacks, {len(android)} XML reports, {len(manifest)} captures; native review pending.')
