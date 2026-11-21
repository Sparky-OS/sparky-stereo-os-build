#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""xshot.py OUT.png: the root window of $DISPLAY as a PNG, through Xlib's GetImage (for an X server with no compositor)."""
import sys
from PIL import Image
from Xlib import X, display
d = display.Display(); r = d.screen().root; g = r.get_geometry()
img = r.get_image(0, 0, g.width, g.height, X.ZPixmap, 0xffffffff)
Image.frombytes("RGB", (g.width, g.height), img.data, "raw", "BGRX").save(sys.argv[1])
print(g.width, g.height)
