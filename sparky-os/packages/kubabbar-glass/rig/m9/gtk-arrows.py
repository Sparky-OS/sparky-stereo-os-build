#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""gtk-arrows.py CAPTURE.png REPORT.json ASSETS EXPECT: where the scroll arrows of a GTK gallery's two scroll bars are.

Each arrow box of the theme (ASSETS/sarrowbox-{up,down,left,right}-normal.png) is found in the capture inside the bar's
rectangle by an exact match of its pixels; the vertical bar's arrows are placed by their row, the horizontal bar's by
their column. EXPECT is together (both at the far end, the backward one first), apart (one at each end) or none (GTK 4,
which has no scroll arrows). Prints one line per bar and PASS or FAIL; exits 1 on FAIL."""
import json
import sys

import numpy as np
from PIL import Image

cap = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
rep = json.load(open(sys.argv[2]))
assets, expect = sys.argv[3], sys.argv[4]


def find(name, rect):
    pic = np.asarray(Image.open(f"{assets}/sarrowbox-{name}-normal.png").convert("RGBA")).astype(int)
    opaque = pic[..., 3] == 255
    x, y, w, h = rect
    ph, pw = pic.shape[:2]
    hits = []
    for yy in range(y - 2, y + h - ph + 3):
        for xx in range(x - 2, x + w - pw + 3):
            win = cap[yy:yy + ph, xx:xx + pw]
            if win.shape[:2] == (ph, pw) and np.abs(win - pic[..., :3])[opaque].max(initial=0) <= 2:
                hits.append((xx - x, yy - y))
    return hits


ok = True
for bar, (back, fwd, axis) in {"v": ("up", "down", 1), "h": ("left", "right", 0)}.items():
    rect = rep["bars"][bar]
    length = rect[3] if bar == "v" else rect[2]
    b, f = find(back, rect), find(fwd, rect)
    pos_b = sorted(p[axis] for p in b)
    pos_f = sorted(p[axis] for p in f)
    if expect == "none":
        good = not b and not f
    elif not (len(b) == 1 and len(f) == 1):
        good = False
    elif expect == "together":
        good = pos_f[0] >= length - 16 - 2 and pos_b[0] >= length - 32 - 2 and pos_b[0] < pos_f[0]
    else:
        good = pos_b[0] <= 2 and pos_f[0] >= length - 16 - 2
    ok &= good
    print(f"{bar} bar {rect}: {back} at {pos_b}, {fwd} at {pos_f}, expected {expect}: {'PASS' if good else 'FAIL'}")
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
