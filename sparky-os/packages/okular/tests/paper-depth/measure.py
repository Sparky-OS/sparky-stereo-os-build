#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""measure.py CASE_DIR KIND -- the paper depth proof's measurements of one case, as one JSON object on stdout.

KIND is okular (a magenta desk, 255,0,255, Okular's custom background) or preview (Qt's print preview, a Qt::gray desk,
160,160,164). The capture (shot.png) holds both eyes side by side, left first, each 1920 wide; a 2D capture is one picture.

- pages: the white pages inside the program's window (KWin's frame from windows.json), found in the left eye.
- disparity of a region: the horizontal shift s that best maps the left eye's region onto the right eye's along the same
  rows (left(x) = right(x - s)), searched from -20 to 20 whole pixels; s is the left eye's position minus the right eye's,
  negative behind the window's plane. The residual (mean absolute difference at s) says whether the match is real.
  Regions: each page's interior (the paper); a strip of desk just below each page holding the start of the page's bottom
  shadow (the desk); the window's title bar (the window's plane). For a page run under the toolbar (no bottom in view):
  the page's interior just under the view's top edge, and the page's right edge column of outline in each eye.
- differing: how many pixels differ between the eyes, and the box they lie in.
"""
import json
import sys

import numpy as np
from PIL import Image

case_dir, kind = sys.argv[1], sys.argv[2]
desk_colour = np.array((255, 0, 255) if kind == "okular" else (160, 160, 164))
shot = np.asarray(Image.open(f"{case_dir}/shot.png").convert("RGB")).astype(np.int16)
height, width, _ = shot.shape
stereo = width >= 2 * 1920
left = shot[:, : width // 2] if stereo else shot
right = shot[:, width // 2:] if stereo else shot
result = {"capture": [width, height], "stereo": stereo}

windows = []
try:
    with open(f"{case_dir}/windows.json") as f:
        for line in f:
            line = line.strip()
            if line.startswith("["):
                windows = json.loads(line)
except (OSError, ValueError):
    pass
names = ("okular",) if kind == "okular" else ("paper-depth-preview",)
program = [w for w in windows if any(n in (w.get("caption", "") + " " + w.get("cls", "")).lower() for n in names)
           and w.get("normal") and not w.get("deleted")]
frame = program[0]["fg"] if program else [0, 0, 1920, 1080]
result["frame"] = frame
x0, y0, fw, fh = (int(round(v)) for v in frame)
x1, y1 = min(x0 + fw, left.shape[1]), min(y0 + fh, left.shape[0])
x0, y0 = max(x0, 0), max(y0, 0)

# the desk inside the window: where the view is
desk = (np.abs(left - desk_colour).max(axis=2) <= 3)
desk[:y0] = False
desk[y1:] = False
desk[:, :x0] = False
desk[:, x1:] = False
ys, xs = np.nonzero(desk)
view = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None
result["desk_box"] = view

# the pages: runs of white rows inside the view, then runs of white columns in each band
pages = []
if view:
    vx0, vy0, vx1, vy1 = view
    white = (left[vy0:vy1 + 1, vx0:vx1 + 1] >= 245).all(axis=2)
    rows = white.sum(axis=1) > 40
    y = 0
    while y < len(rows):
        if rows[y]:
            start = y
            while y < len(rows) and rows[y]:
                y += 1
            band = white[start:y]
            cols = band.sum(axis=0) > max(3, (y - start) // 2)
            x = 0
            while x < len(cols):
                if cols[x]:
                    cstart = x
                    while x < len(cols) and cols[x]:
                        x += 1
                    if x - cstart > 40 and y - start > 20:
                        pages.append([vx0 + cstart, vy0 + start, vx0 + x - 1, vy0 + y - 1])
                else:
                    x += 1
        else:
            y += 1
result["pages"] = pages


def disparity(box):
    """The shift s with left(x) = right(x - s) over box (left eye coordinates), and its residual."""
    bx0, by0, bx1, by1 = box
    bx0, by0 = max(bx0, 21), max(by0, 0)
    bx1, by1 = min(bx1, left.shape[1] - 22), min(by1, left.shape[0] - 1)
    if bx1 <= bx0 or by1 < by0:
        return None
    patch = left[by0:by1 + 1, bx0:bx1 + 1]
    if patch.std() < 1:
        return {"box": [bx0, by0, bx1, by1], "shift": None, "why": "uniform: nothing to match"}
    best = None
    for s in range(-20, 21):
        other = right[by0:by1 + 1, bx0 - s:bx1 + 1 - s]
        err = float(np.abs(patch - other).mean())
        if best is None or err < best[1]:
            best = (s, err)
    return {"box": [bx0, by0, bx1, by1], "shift": best[0], "residual": round(best[1], 3)}


measures = []
for i, (px0, py0, px1, py1) in enumerate(pages):
    entry = {"page": i, "box": [px0, py0, px1, py1]}
    entry["paper"] = disparity([px0 + 8, py0 + 8, px1 - 8, py1 - 8])
    if view and py1 + 6 <= view[3]:
        # the desk just below the page (under its bottom outline, which is the paper's): the page's bottom shadow starts
        # near the page's left edge
        entry["desk"] = disparity([px0 - 40, py1 + 2, px0 + 60, py1 + 6])
    if view and py0 <= view[1] + 1:
        # the page runs under the top of the view: its interior right under the cut, and its right edge of outline
        entry["paper_at_cut"] = disparity([px0 + 8, py0, px1 - 8, py0 + 20])
        edges = []
        for eye in (left, right):
            row = eye[py0 + 10, px1 - 5: px1 + 30]
            dark = np.nonzero(row.max(axis=1) < 60)[0]
            edges.append(int(px1 - 5 + dark[0]) if len(dark) else None)
        entry["outline_right_at_cut"] = edges
    measures.append(entry)
result["measures"] = measures
if program and stereo:
    # the title bar: the window's own plane
    result["title_bar"] = disparity([x0 + 200, y0 + 4, x0 + min(fw, 900), y0 + 24])

diff = np.abs(left - right).max(axis=2) > 0
dys, dxs = np.nonzero(diff)
result["differing"] = int(diff.sum())
result["differing_box"] = [int(dxs.min()), int(dys.min()), int(dxs.max()), int(dys.max())] if len(dxs) else None
json.dump(result, sys.stdout)
print()
