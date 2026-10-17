#!/usr/bin/env python3
# Measures a screenshot of the marker pattern (proof/make-markers.py): the red-only and the cyan-only marker
# (left and right eye) and their horizontal distance, and the 2D parts (grey bar, white block): equal R, G, B.
import sys
import numpy as np
from PIL import Image
for path in sys.argv[1:]:
    a = np.asarray(Image.open(path).convert("RGB")).astype(int); r, g, b = a[..., 0], a[..., 1], a[..., 2]
    red = (r > 200) & (g < 40) & (b < 40); cyan = (r < 40) & (g > 200) & (b > 200)
    def box(m):
        ys, xs = np.nonzero(m)
        return (xs.min(), xs.max(), ys.min(), ys.max(), int(m.sum())) if xs.size else None
    rb, cb = box(red), box(cyan)
    rb = rb and tuple(int(v) for v in rb); cb = cb and tuple(int(v) for v in cb)
    bar = a[10:50, 200:1000]; block = a[110:190, 50:130]
    neutral = lambda p: (int(np.abs(p[..., 0] - p[..., 1]).max()), int(np.abs(p[..., 1] - p[..., 2]).max()))
    line = f"{path.split('/')[-1]}: red-only {rb}, cyan-only {cb}"
    if rb and cb:
        # the markers are 101 px wide and overlap in white: left marker from the red edge, right marker to the cyan edge
        line += f"; left marker x {rb[0]}..{rb[0] + 100}, right marker x {cb[1] - 100}..{cb[1]}, disparity {cb[1] - 100 - rb[0]:+d} px (drawn +80), same rows: {rb[2:4] == cb[2:4]}"
    line += f"; bar max |R-G|,|G-B| {neutral(bar)}, block {neutral(block)}"
    print(line)
