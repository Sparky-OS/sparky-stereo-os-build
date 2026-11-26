#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""sheet.py OUT.png CLASS_OR_CAPTION CASE... : the same window cut from each case's apps.png by its KWin frame
(win-apps.json), side by side with the case's name above it; for a 3D capture the left eye."""
import json
import os
import sys

from PIL import Image, ImageDraw

out, key, cases = sys.argv[1], sys.argv[2], sys.argv[3:]
cuts = []
for case in cases:
    img = Image.open(os.path.join(case, "apps.png")).convert("RGB")
    if img.width > 2 * img.height:
        img = img.crop((0, 0, img.width // 2, img.height))
    wins = json.load(open(os.path.join(case, "win-apps.json")))
    w = next(w for w in wins if key in (w.get("cls") or "") or key == w.get("caption"))
    box = (int(w["x"]), int(w["y"]), int(w["x"] + w["w"]), int(w["y"] + w["h"]))
    cuts.append((os.path.basename(case.rstrip("/")), img.crop(box)))
W = sum(c.width for _, c in cuts) + 12 * (len(cuts) + 1)
H = max(c.height for _, c in cuts) + 40
sheet = Image.new("RGB", (W, H), (255, 255, 255))
draw = ImageDraw.Draw(sheet)
x = 12
for name, c in cuts:
    draw.text((x, 10), name, fill=(0, 0, 0))
    sheet.paste(c, (x, 32))
    x += c.width + 12
sheet.save(out)
print(out, [n for n, _ in cuts])
