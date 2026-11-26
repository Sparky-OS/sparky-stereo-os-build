#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""gtk-sheet.py OUT: one picture of the galleries side by side, GTK 2, GTK 3, GTK 4 and Qt 6, the scroll arrows together
(top row) and apart (bottom row), each gallery's window cut from its capture by the size it reported; the File menu
and the tool tip of GTK 3 beside them. Writes OUT/galleries.png."""
import json
import os
import sys

from PIL import Image, ImageDraw

out = sys.argv[1]
cells, labels = [], []
for arrows in ("together", "apart"):
    row = []
    for kit in ("gtk2", "gtk3", "gtk4"):
        rep = json.load(open(os.path.join(out, f"{arrows}-{kit}.json")))
        w, h = rep["size"]
        row.append((Image.open(os.path.join(out, f"{arrows}-{kit}-window.png")).convert("RGB").crop((0, 0, w, h)),
                    f"{kit.upper()} {rep['gtk']}, {rep['theme']}"))
    qt = Image.open(os.path.join(out, f"{arrows}-qt6.png")).convert("RGB")
    row.append((qt, f"Qt 6, Kvantum ({arrows})"))
    cells.append(row)
scale = 0.6
cw = max(int(im.width * scale) for row in cells for im, _ in row)
ch = max(int(im.height * scale) for row in cells for im, _ in row)
sheet = Image.new("RGB", (4 * (cw + 10) + 10, 2 * (ch + 30) + 10), (255, 255, 255))
draw = ImageDraw.Draw(sheet)
for r, row in enumerate(cells):
    for c, (im, label) in enumerate(row):
        x, y = 10 + c * (cw + 10), 10 + r * (ch + 30)
        draw.text((x, y), label, fill=(0, 0, 0))
        sheet.paste(im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS), (x, y + 18))
sheet.save(os.path.join(out, "galleries.png"))
print("galleries.png", sheet.size)
