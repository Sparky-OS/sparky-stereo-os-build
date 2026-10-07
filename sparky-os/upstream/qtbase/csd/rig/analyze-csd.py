#!/usr/bin/env python3
"""Decoration check for a stereo capture (full side by side, left eye first) of a window drawn with
Qt's own client side decoration around solid stereo content (left red, right green; a blue 2D label
may sit inside the content, it is excluded as content too).

Reports, per eye, the bounding box of the content colour, the number of decoration pixels (everything
outside that box), and whether the decoration is pixel-identical in both eyes. Exit 0 always."""
import sys
import numpy as np
from PIL import Image

rgba = np.asarray(Image.open(sys.argv[1]).convert("RGBA")).astype(int)
img = rgba[..., :3]
h, w = img.shape[:2]
half = w // 2
L, R = img[:, :half], img[:, half:2 * half]
aL, aR = rgba[:, :half, 3], rgba[:, half:2 * half, 3]


def mask(a, c):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    if c == "red":
        return (r > 180) & (g < 80) & (b < 80)
    return (g > 180) & (r < 80) & (b < 80)


def bbox(m):
    ys, xs = np.where(m)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max(), ys.max()


bl, br = bbox(mask(L, "red")), bbox(mask(R, "green"))
print(f"capture {w}x{h}, eye {half}x{h}")
print(f"left content (red) bbox {bl}, right content (green) bbox {br}")
if bl is None or br is None:
    print("content colour missing in an eye")
    sys.exit(0)
for name, (x0, y0, x1, y1) in (("left", bl), ("right", br)):
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    print(f"{name}: content {cw}x{ch}, margins left {x0} top {y0} right {half - 1 - x1} bottom {h - 1 - y1}")
x0, y0, x1, y1 = bl
inside = np.zeros((h, half), bool)
inside[y0:y1 + 1, x0:x1 + 1] = True
deco = ~inside
print(f"decoration pixels (outside the content box): {int(deco.sum())}")
print("same content box in both eyes:", bl == br)
d = np.any(L != R, axis=2)
opaque = (aL == 255) & (aR == 255)
print(f"decoration pixels differing between eyes: {int((d & deco).sum())}"
      f" (of which fully opaque in both eyes: {int((d & deco & opaque).sum())},"
      f" partly transparent corner pixels, alpha<255 in an eye: {int((d & deco & ~opaque).sum())}; alpha<255 pixels in decoration: {int(((aL < 255) & deco).sum())} left, {int(((aR < 255) & deco).sum())} right)")
print(f"opaque decoration identical in both eyes: {not bool((d & deco & opaque).any())}")
nonblack = int((np.any(L > 0, axis=2) & deco).sum())
print(f"non-black decoration pixels (left): {nonblack}")
