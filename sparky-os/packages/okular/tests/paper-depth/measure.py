#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""measure.py CASE_DIR KIND -- the paper depth proof's measurements of one case, as one JSON object on stdout.

KIND is okular (Okular's page view, its desk set to the custom background 255,0,255) or preview (Qt's print preview, its
desk Qt::gray, 160,160,164). The capture (shot.png) holds both eyes side by side, left first, each 1920 wide; a 2D capture
is one picture.

- pages: inside the program's window (KWin's frame from windows.json), in the left eye, the bands of rows and runs of
  columns of paper: white, or one of the marks' pure colours (red, green, blue), so a toolbar's light grey is never paper.
- disparity of a region: the horizontal shift s that best maps the left eye's region onto the right eye's along the same
  rows (left(x) = right(x - s)), searched from -20 to 20 whole pixels; s is the left eye's position minus the right eye's,
  negative behind the window's plane. The residual (mean absolute difference at s) says whether the match is real; a
  region whose best shift is not the only one (a uniform or striped region) gives no shift.
  Regions: each page's interior (the paper); the rows of the page's bottom shadow under it, from left of the page to
  past its left edge, where the shadow starts (the desk; the outline row, which is the paper's, is left out); the
  window's title bar (the window's plane). A page whose top is cut by something that is neither its outline nor the desk
  runs under the toolbar: its interior right under the cut, and the first column right of it that is not paper, in each eye.
- differing: how many pixels differ between the eyes, and the box they lie in.
"""
import json
import sys

import numpy as np
from PIL import Image

case_dir, kind = sys.argv[1], sys.argv[2]
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
            if line.startswith("{"):
                windows = json.loads(line).get("windows") or []
except (OSError, ValueError):
    pass
names = {"okular": ("okular",), "preview": ("paper-depth-preview",),
         "words": ("calligrawords", "calligra words")}[kind]
program = [w for w in windows if any(n in (w.get("caption", "") + " " + w.get("cls", "")).lower() for n in names)
           and w.get("normal") and not w.get("deleted")]
frame = program[0]["fg"] if program else [0, 0, 1920, 1080]
result["frame"] = frame
x0, y0, fw, fh = (int(round(v)) for v in frame)
x1, y1 = min(x0 + fw, left.shape[1]), min(y0 + fh, left.shape[0])
x0, y0 = max(x0, 0), max(y0, 0)

desk_colour = np.array((255, 0, 255) if kind == "okular" else (160, 160, 164))
result["desk_colour"] = [int(v) for v in desk_colour]


def is_desk(pixels):
    return np.abs(pixels - desk_colour).max(axis=-1) <= 3


def is_paper(pixels):
    white = (pixels >= 250).all(axis=-1)
    if kind == "words":
        return white
    pure = (pixels.max(axis=-1) >= 200) & (pixels.min(axis=-1) <= 60) & ~is_desk(pixels)
    return white | pure


pages = []
area = left[y0:y1, x0:x1]
paper = is_paper(area)
rows = paper.sum(axis=1) > 40
y = 0
while y < len(rows):
    if rows[y]:
        start = y
        while y < len(rows) and rows[y]:
            y += 1
        band = paper[start:y]
        cols = band.sum(axis=0) > max(3, (y - start) // 2)
        x = 0
        while x < len(cols):
            if cols[x]:
                cstart = x
                while x < len(cols) and cols[x]:
                    x += 1
                # the page's own rows: a band is shared by everything side by side in it
                own = np.nonzero(band[:, cstart:x].sum(axis=1) > (x - cstart) // 2)[0]
                if x - cstart > 150 and len(own):
                    # one page per run of its own rows (pages one under the other in one band)
                    for run in np.split(own, np.nonzero(np.diff(own) > 1)[0] + 1):
                        if run[-1] - run[0] > 60:
                            pages.append([x0 + cstart, y0 + start + int(run[0]), x0 + x - 1, y0 + start + int(run[-1])])
            else:
                x += 1
    else:
        y += 1
# a page under a window stacked above the program's is not the program's
if program:
    above = windows[windows.index(program[0]) + 1:]
    def covered(box):
        bx0, by0, bx1, by1 = box
        for w in above:
            if w.get("deleted") or w.get("hidden"):
                continue
            wx, wy, ww, wh = w["fg"]
            if bx0 < wx + ww and wx < bx1 and by0 < wy + wh and wy < by1:
                return True
        return False
    pages = [box for box in pages if not covered(box)]
result["pages"] = pages


def disparity(box):
    """The shift s with left(x) = right(x - s) over box (left eye coordinates), its residual, and whether it is the
    only best shift."""
    bx0, by0, bx1, by1 = box
    bx0, by0 = max(bx0, 21), max(by0, 0)
    bx1, by1 = min(bx1, left.shape[1] - 22), min(by1, left.shape[0] - 1)
    if bx1 <= bx0 or by1 < by0:
        return None
    patch = left[by0:by1 + 1, bx0:bx1 + 1]
    if patch.std() < 1:
        return {"box": [bx0, by0, bx1, by1], "shift": None, "why": "uniform: nothing to match"}
    errors = []
    for s in range(-20, 21):
        other = right[by0:by1 + 1, bx0 - s:bx1 + 1 - s]
        errors.append((float(np.abs(patch - other).mean()), s))
    errors.sort()
    best_err, best = errors[0]
    ties = [s for err, s in errors if err <= best_err + 0.01]
    if len(ties) > 1:
        return {"box": [bx0, by0, bx1, by1], "shift": None, "why": f"ambiguous: shifts {sorted(ties)} match alike",
                "residual": round(best_err, 3)}
    return {"box": [bx0, by0, bx1, by1], "shift": best, "residual": round(best_err, 3)}


def shadow_rows(px0, px1, py1):
    """The rows under a page that hold its bottom shadow: below its last row of paper, at the page's middle, the rows
    that are neither the desk nor paper nor near black (an outline, or a shadow's darkest row, which has no left end)."""
    xm = (px0 + px1) // 2
    found = []
    for y in range(py1 + 1, min(py1 + 30, y1, left.shape[0])):
        pixel = left[y, xm]
        if is_desk(pixel) and found:
            break
        if not is_desk(pixel) and not is_paper(pixel) and pixel.max() >= 40:
            found.append(y)
    return found


def words_pages_and_desk():
    # The proof's style supplies a patterned brush to KWCanvas. It reaches the
    # painted gap between pages through Words' ordinary eraseRect() call.
    canvas_area = left[y0:y1, x0:x1]
    ink = (canvas_area[:, :, 1] == 24) & (canvas_area[:, :, 2] == 140)
    rows, columns = np.nonzero(ink)
    if not len(rows):
        return [], None
    cx0, cx1 = x0 + int(columns.min()), x0 + int(columns.max())
    cy0, cy1 = y0 + int(rows.min()), y0 + int(rows.max())
    desk = disparity([cx0 + 24, cy0, cx1 - 24, cy1])

    # Keep white page runs inside the canvas width. Blank white around the
    # canvas may also form a run, but has no shift that can be measured.
    top = y0 + 84
    stripe = left[top:y1 - 60, cx0 + 8:cx1 - 8]
    visible = np.flatnonzero(is_paper(stripe).mean(axis=1) > 0.6)
    page_boxes = []
    for band in np.split(visible, np.nonzero(np.diff(visible) > 1)[0] + 1):
        if len(band) <= 45:
            continue
        a, b = top + int(band[0]), top + int(band[-1])
        box = [cx0, a, cx1, b]
        measured = disparity([cx0 + 8, a + 4, cx1 - 8, b - 4])
        if measured and measured["shift"] is not None:
            page_boxes.append(box)
    return page_boxes, desk


if kind == "words":
    pages, result["desk"] = words_pages_and_desk()
    result["pages"] = pages


def cut_at_top(px0, px1, py0):
    """Whether the page's top is cut by something above it that is neither its outline (near black), its desk nor paper."""
    xm = (px0 + px1) // 2
    above = left[max(py0 - 2, 0):py0, xm]
    return len(above) > 0 and all(not is_desk(p) and not is_paper(p) and p.max() >= 60 for p in above)


measures = []
for i, (px0, py0, px1, py1) in enumerate(pages):
    entry = {"page": i, "box": [px0, py0, px1, py1]}
    entry["paper"] = disparity([px0 + 8, py0 + 8, px1 - 8, py1 - 8])
    rows_below = [] if kind == "words" else shadow_rows(px0, px1, py1)
    if rows_below:
        entry["shadow_rows"] = [rows_below[0], rows_below[-1]]
        entry["desk"] = disparity([px0 - 40, rows_below[0], px0 + 60, rows_below[-1]])
    cut = py0 <= y0 + 87 if kind == "words" else cut_at_top(px0, px1, py0)
    if cut:
        entry["paper_at_cut"] = disparity([px0 + 8, py0, px1 - 8, py0 + 20])
        edges = []
        for eye in (left, right):
            row = eye[py0 + 10, px1 - 5: px1 + 30]
            beyond = np.nonzero(~is_paper(row))[0]
            edges.append(int(px1 - 5 + beyond[0]) if len(beyond) else None)
        entry["right_edge_at_cut"] = edges
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
