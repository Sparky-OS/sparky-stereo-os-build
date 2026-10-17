#!/usr/bin/env python3
"""sheet.py RUNDIR [OUT.png] [COLS] : the run's frames in time order, scaled to 320 px wide, labelled, on one sheet."""
import os, sys
from PIL import Image, ImageDraw
d = sys.argv[1]; out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(d, "sheet.png"); cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
def key(n):
    digits = "".join(c for c in n if c.isdigit())
    return (0 if n.startswith("m") else 1, int(digits) if digits else 0, n)
frames = sorted([f for f in os.listdir(d) if f.endswith(".png") and f != "sheet.png"], key=key)
W = 320; tiles = []
for f in frames:
    im = Image.open(os.path.join(d, f)).convert("RGB")
    h = int(im.height * W / im.width); im = im.resize((W, h))
    t = Image.new("RGB", (W, h + 16), (40, 40, 40)); t.paste(im, (0, 16))
    ImageDraw.Draw(t).text((4, 2), f[:-4], fill=(255, 255, 0)); tiles.append(t)
th = max(t.height for t in tiles); rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W, rows * th), (0, 0, 0))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * W, (i // cols) * th))
sheet.save(out); print(out, sheet.size)
