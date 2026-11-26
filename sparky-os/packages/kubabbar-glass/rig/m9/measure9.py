#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""measure9.py glass CASE | depth CASE: Kubabbar Glass 9's session measurements, written beside the case.
glass  the levels the translucency probe and the widget step read (alpha 8-bit medians), against Kubabbar Glass
       20261126's: the panel's bottom edge 129, pop-ups and the launcher 157, widgets 80, inactive windows and dialogs 232
depth  on a 3D output, each window's disparity (right eye minus left, device pixels): the horizontal shift that makes
       the right eye's pixels inside the window's KWin frame (8 pixels in from its edges) equal the left eye's, searched
       from -16 to 16, with the residual of the best and of the second best shift"""
import json
import os
import sys

import numpy as np
from PIL import Image

EXPECTED = {"panel": 129, "notification": 157, "launcher-popup": 157, "probe-inactive": 232, "probe-dialog": 232,
            "widget": 80}


def glass(case):
    g = json.load(open(os.path.join(case, "glass.json")))
    w = json.load(open(os.path.join(case, "widget.json"))) if os.path.exists(os.path.join(case, "widget.json")) else {}
    rows = []
    for key, val in g.items():
        name = "panel" if key.startswith("panel@") else key
        if name in EXPECTED:
            got = val.get("alpha_8bit_median")
            rows.append({"surface": key, "measured": got, "kubabbar_glass_20261126": EXPECTED[name],
                         "equal": got == EXPECTED[name], "frame": val.get("frame")})
        elif key == "probe-active":
            rows.append({"surface": key, "measured": val.get("alpha_8bit_median"), "note": val.get("note"),
                         "kubabbar_glass_20261126": "opaque (no translucent pixel)"})
    for applet, val in w.items():
        got = val.get("alpha_8bit_median")
        if got is not None:
            rows.append({"surface": "widget " + applet, "measured": got, "kubabbar_glass_20261126": 80, "equal": got == 80,
                         "frame": val.get("frame")})
    json.dump(rows, open(os.path.join(case, "glass-table.json"), "w"), indent=1)
    for r in rows:
        print(r)


def depth(case):
    img = np.asarray(Image.open(os.path.join(case, "apps.png")).convert("L")).astype(float)
    half = img.shape[1] // 2
    L, R = img[:, :half], img[:, half:]
    # KWin's stacking order, bottom to top: each window is measured only where no window above it covers it, every
    # covering frame widened by 24 pixels (more than the largest shift searched, and its shadow)
    wins = json.load(open(os.path.join(case, "win-apps.json")))
    rows = []
    for i, w in enumerate(wins):
        if not (w.get("normal") or w.get("dock")) or w["w"] < 100:
            continue
        x0, y0 = int(w["x"]) + 8, int(w["y"]) + 8
        x1, y1 = int(w["x"] + w["w"]) - 8, int(w["y"] + w["h"]) - 8
        x0, x1 = max(x0, 20), min(x1, half - 20)
        if x1 - x0 < 40 or y1 - y0 < 40:
            continue
        mask = np.ones((y1 - y0, x1 - x0), bool)
        for o in wins[i + 1:]:
            if o.get("desktop") or o["w"] < 2:
                continue
            ox0, oy0 = int(o["x"]) - 24 - x0, int(o["y"]) - 24 - y0
            ox1, oy1 = int(o["x"] + o["w"]) + 24 - x0, int(o["y"] + o["h"]) + 24 - y0
            mask[max(oy0, 0):max(oy1, 0), max(ox0, 0):max(ox1, 0)] = False
        visible = int(mask.sum())
        if visible < 2000:
            rows.append({"window": w.get("caption", "")[:60], "class": w.get("cls"), "active": w.get("active"),
                         "dock": w.get("dock"), "visible_pixels": visible, "note": "covered by the windows above"})
            continue
        errs = {}
        for d in range(-16, 17):
            a = L[y0:y1, x0:x1]
            b = R[y0:y1, x0 + d:x1 + d]
            errs[d] = float(np.mean(np.abs(a - b)[mask]))
        best = sorted(errs, key=errs.get)
        rows.append({"window": w.get("caption", "")[:60], "class": w.get("cls"), "active": w.get("active"),
                     "dock": w.get("dock"), "visible_pixels": visible, "disparity": best[0],
                     "residual": round(errs[best[0]], 2), "next_residual": round(errs[best[1]], 2)})
    json.dump(rows, open(os.path.join(case, "depth.json"), "w"), indent=1)
    for r in rows:
        print(r)


{"glass": glass, "depth": depth}[sys.argv[1]](sys.argv[2])
