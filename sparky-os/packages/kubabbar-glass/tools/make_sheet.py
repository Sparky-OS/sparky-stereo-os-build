#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Tile numbered frames into one contact sheet: make_sheet.py OUT.png COLUMNS SCALE FRAME.png...  (each frame is labelled with its time if LABELS is a JSON list of seconds)"""
import json
import os
import sys
from PIL import Image, ImageDraw

out, columns, scale, frames = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4:]
labels = json.loads(os.environ.get("LABELS", "[]"))
images = [Image.open(f).convert("RGB") for f in frames]
w, h = int(images[0].width * scale), int(images[0].height * scale)
rows = (len(images) + columns - 1) // columns
sheet = Image.new("RGB", (w * columns, h * rows), "white")
for i, image in enumerate(images):
    tile = image.resize((w, h), Image.LANCZOS)
    if i < len(labels):
        ImageDraw.Draw(tile).text((8, h - 18), "t = %s s" % labels[i], fill="#ffff00")
    sheet.paste(tile, ((i % columns) * w, (i // columns) * h))
sheet.save(out)
print(out, sheet.size)
