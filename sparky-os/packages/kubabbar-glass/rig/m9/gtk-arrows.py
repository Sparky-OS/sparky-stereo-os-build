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


def found(picture, rect, face_picture):
    """The picture in the rectangle, composited over the scroll box's face (the interior of face_picture): at a whole
    pixel, or at half a pixel across, along or both, since GTK 3 and 4 centre a background picture at half a pixel when the
    box's length is odd (each row or column then the mean of two neighbouring ones)."""
    pic = np.asarray(Image.open(f"{assets}/{picture}.png").convert("RGBA")).astype(float)
    fp = np.asarray(Image.open(f"{assets}/{face_picture}.png").convert("RGB")).astype(float)
    face = fp[fp.shape[0] // 2, fp.shape[1] // 2]
    a = pic[..., 3:4] / 255
    comp = pic[..., :3] * a + face * (1 - a)
    padded = np.pad(comp, ((1, 1), (1, 1), (0, 0)), mode="constant")
    padded[0, :], padded[-1, :], padded[:, 0], padded[:, -1] = face, face, face, face
    both = (padded[:-1, :-1] + padded[1:, :-1] + padded[:-1, 1:] + padded[1:, 1:]) / 4
    variants = [comp, (padded[:-1, 1:-1] + padded[1:, 1:-1]) / 2, (padded[1:-1, :-1] + padded[1:-1, 1:]) / 2, both]
    x, y, w, h = rect
    for i, v in enumerate(variants):
        # a half-pixel picture is GTK's resampling of rows that are themselves partly covered: 16 levels (measured 13
        # on GTK 3, against 89 at every other place); a whole-pixel one within rounding
        limit = 6 if i == 0 else 16
        vh, vw = v.shape[:2]
        for yy in range(y - 2, y + h - vh + 3):
            for xx in range(x - 2, x + w - vw + 3):
                win = cap[yy:yy + vh, xx:xx + vw]
                if win.shape[:2] == (vh, vw) and np.abs(win - v).max() <= limit:
                    return True
    return False


ok = True
# the theme is drawn: the scroll box's grip, the theme's own picture, is in each bar (GTK 4's bars have no arrows, so
# without this a bar that the theme never reached would pass as "none")
for bar, grip in (("v", "grip-normal"), ("h", "grip-h-normal")):
    has = found(grip, rep["bars"][bar], "scrollbarslider-normal")
    ok &= has
    print(f"{bar} bar: the scroll box's grip {'found' if has else 'NOT found'}")
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
