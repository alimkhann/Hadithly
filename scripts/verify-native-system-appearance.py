#!/usr/bin/env python3
"""Verify a DEBUG iOS app follows live System appearance without relaunching."""
import argparse
from pathlib import Path
import os
import subprocess
import time
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--device', required=True, help='Explicit simulator UUID')
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def sim(*command, **kwargs):
    return subprocess.run(['xcrun', 'simctl', *command], check=True, capture_output=True, text=True, **kwargs).stdout.strip()

original = sim('ui', args.device, 'appearance')
if original not in ('light', 'dark'):
    raise RuntimeError(f'Unexpected simulator appearance: {original}')

try:
    sim('ui', args.device, 'appearance', 'dark')
    subprocess.run(['xcrun', 'simctl', 'terminate', args.device, 'com.hadithly.app'], capture_output=True)
    environment = dict(os.environ, SIMCTL_CHILD_HADITHLY_UI_TESTING='1', SIMCTL_CHILD_FINISH_SCREEN='fresh-install')
    sim('launch', args.device, 'com.hadithly.app', '-NativeFinishingFixture', env=environment)
    samples = {}
    for style in ('dark', 'light', 'dark'):
        sim('ui', args.device, 'appearance', style)
        path = args.output / f'system-{style}.png'
        for attempt in range(20):
            time.sleep(0.4)
            sim('io', args.device, 'screenshot', str(path))
            with Image.open(path) as image:
                rgb = image.convert('RGB').getpixel((10, image.height // 2))
            if (max(rgb) < 80 if style == 'dark' else min(rgb) > 180):
                break
        else:
            raise AssertionError(f'System {style} did not update the live app: {rgb}')
        samples[style] = rgb
    (args.output / 'system-appearance.txt').write_text(f'Live dark -> light -> dark passed without relaunch. Canvas samples: {samples}\n')
    print('PASS: live System appearance follows dark -> light -> dark without relaunch')
finally:
    sim('ui', args.device, 'appearance', original)
