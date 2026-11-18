#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Reads one run of glx-child-first-pair (stdout and the Stereo KWin capture) and says whether the first swap of a declared child gave a pair.

usage: check-glx-child-first-pair.py CLIENT_STDOUT CAPTURE_PNG OUTPUT_WIDTH [--control-flat]

PAIR   the capture is twice the output wide, the child still declares (CONTENT 3) two seconds after its one swap, no "shown flat" line.
FLAT   the capture is one output wide, the declaration is gone, and Mesa told the person ("is shown flat").
Exit 0 when the run is a PAIR (or a FLAT with --control-flat: the run on a stack without the fix), 1 otherwise.
"""
import sys
from PIL import Image

out, png, width = sys.argv[1], sys.argv[2], int(sys.argv[3])
control = '--control-flat' in sys.argv[4:]
text = open(out, errors='replace').read()
w = Image.open(png).size[0]
declared = 'later _KDE_NET_WM_STEREO_CONTENT: 3' in text.replace('2 s ', '')
told = 'is shown flat' in text
state = 'PAIR' if w == 2 * width and declared and not told else 'FLAT' if w == width and not declared and told else 'OTHER'
print(f'{state}: capture {w} wide (output {width}), declared at the end {declared}, told {told}')
sys.exit(0 if state == ('FLAT' if control else 'PAIR') else 1)
