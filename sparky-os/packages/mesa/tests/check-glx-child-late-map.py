#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""Reads one run of glx-child-late-map (stdout and the Stereo KWin capture) and says whether the child became a pair once its window was mapped.

usage: check-glx-child-late-map.py CLIENT_STDOUT CAPTURE_PNG OUTPUT_WIDTH [--control-flat] [--remaps N]

PAIR   the capture is twice the output wide, the child is declared after the map (CONTENT 3), no "shown flat" line.
FLAT   the capture is one output wide, the child is not declared.
Exit 0 when the run is a PAIR (a FLAT with --control-flat: the run on a stack without the fix), 1 otherwise.
"""
import sys
from PIL import Image

out, png, width = sys.argv[1], sys.argv[2], int(sys.argv[3])
control = '--control-flat' in sys.argv[4:]
text = open(out, errors='replace').read()
w = Image.open(png).size[0]
declared = 'after map _KDE_NET_WM_STEREO_CONTENT: 3' in text
if '--remaps' in sys.argv:
    n = int(sys.argv[sys.argv.index('--remaps') + 1])
    declared = declared and all(f'after remap {k}  _KDE_NET_WM_STEREO_CONTENT: 3' in text for k in range(1, n + 1))
told = 'is shown flat' in text
state = 'PAIR' if w == 2 * width and declared and not told else 'FLAT' if w == width and not declared else 'OTHER'
print(f'{state}: capture {w} wide (output {width}), declared after the map {declared}, told {told}')
sys.exit(0 if state == ('FLAT' if control else 'PAIR') else 1)
