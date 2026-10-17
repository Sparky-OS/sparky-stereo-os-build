#!/usr/bin/env python3
# The measuring pattern of the contributor VM (contributor-vm/out/build-scripts/make-samples.py, section 2):
# full side by side, left eye first, PNG sTER mode 1; a white marker at +80 px disparity, a grey bar and two
# blocks identical in both eyes. Usage: make-markers.py OUT.png [W H]
import struct, sys, zlib
from PIL import Image, ImageDraw
out = sys.argv[1]; W = int(sys.argv[2]) if len(sys.argv) > 2 else 1280; H = int(sys.argv[3]) if len(sys.argv) > 3 else 800
def pattern(eye):
    im = Image.new("RGB", (W, H), (0, 0, 0)); d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 60], fill=(128, 128, 128))
    d.rectangle([40, 100, 140, 200], fill=(255, 255, 255))
    x = W // 2 + eye * 40
    d.rectangle([x - 50, H // 2 - 50, x + 50, H // 2 + 50], fill=(255, 255, 255))
    d.rectangle([W - 200, H - 150, W - 60, H - 60], fill=(60, 60, 60))
    return im
o = Image.new("RGB", (2 * W, H)); o.paste(pattern(-1), (0, 0)); o.paste(pattern(+1), (W, 0)); o.save(out, optimize=True)
d = open(out, "rb").read(); i = d.index(b"IDAT") - 4; body = b"sTER" + b"\x01"
open(out, "wb").write(d[:i] + struct.pack(">I", 1) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF) + d[i:])
