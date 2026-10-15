#!/usr/bin/env python3
"""Measure shared native surface hierarchy and text contrast from source tokens."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
swift = (ROOT / 'ios/Hadithly/Core/Theme/ReaderPalette.swift').read_text()
kotlin = (ROOT / 'android/app/src/main/kotlin/com/hadithly/app/core/theme/Theme.kt').read_text()

def luminance(color):
    channels = [int(color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4 for c in channels]
    return sum(c * w for c, w in zip(linear, (.2126, .7152, .0722)))

def contrast(a, b):
    lo, hi = sorted((luminance(a), luminance(b)))
    return (hi + .05) / (lo + .05)

for theme in ('light', 'paper', 'dark'):
    block = re.search(rf'static let {theme} = ReaderPalette\((.*?)\n    \)', swift, re.S).group(1)
    values = dict(re.findall(r'(\w+): Color\(hex: "([A-Fa-f0-9]+)"\)', block))
    if theme != 'dark':
        android = re.search(rf'val {theme} = HadithlyColors\((.*?)\n    \)', kotlin, re.S).group(1)
        for token in ('background', 'surface', 'surfaceElevated', 'textPrimary', 'textSecondary', 'divider'):
            match = re.search(rf'{token} = Color\(0xFF([A-Fa-f0-9]+)\)', android)
            assert match and match.group(1).upper() == values[token].upper(), f'{theme}.{token}: native palettes differ'
    surface_values = [values[t] for t in ('background', 'surface', 'surfaceElevated')]
    assert len(set(surface_values)) == 3, f'{theme}: three distinct surfaces required'
    print(theme, 'surfaces', '/'.join(surface_values))
    for text in ('textPrimary', 'textSecondary'):
        for surface in ('background', 'surface', 'surfaceElevated'):
            ratio = contrast(values[text], values[surface])
            print(f'  {text}/{surface}: {ratio:.2f}:1')
            assert ratio >= 4.5, f'{theme}.{text}/{surface}: {ratio:.2f} below 4.5:1'
