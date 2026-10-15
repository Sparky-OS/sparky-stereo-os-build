#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""One picture of the four application styles of Kubabbar Glass, each named, from the 2D gallery captures."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OPTIONS = (("breeze", "Breeze: the Quick Settings look (default)"), ("fusion", "Fusion: bevelled, the palette on Qt's own style"),
           ("kvantum", "Kvantum: KvGnome shapes in the palette"), ("oxygenqt", "Oxygen: Oxygen's controls in the palette"))
sheet = Image.new("RGB", (1600, 900), (30, 32, 28))
draw = ImageDraw.Draw(sheet)
for index, (name, label) in enumerate(OPTIONS):
    capture = Image.open(ROOT / ("evidence/m2-%s-classic-2d/desktop.png" % name)).convert("RGB").crop((0, 40, 1600, 880)).resize((800, 420), Image.LANCZOS)
    x, y = (index % 2) * 800, (index // 2) * 450 + 30
    sheet.paste(capture, (x, y))
    draw.text((x + 10, y - 22), label, fill=(255, 255, 255))
out = ROOT / "evidence/m2/options.png"
sheet.save(out)
print(out)
