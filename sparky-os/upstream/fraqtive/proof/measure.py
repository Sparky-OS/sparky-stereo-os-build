#!/usr/bin/env python3
"""measure.py [--assert] PNG...: how much of Fraqtive's 3D view area a capture draws.

The area is found from the layout of each route (X11 maximises the window, Wayland keeps its size); a name holding "-xcb-"
means the X11 route. Prints the number of distinct colours, the share of non-black pixels and the commonest colour with
its share. With --assert the exit status is 1 unless every *-3d.png has at least 1000 colours and 30 % non-black pixels:
a 3D view that drew nothing is one flat colour (Wayland, the window's grey) or 0.1 % non-black (X11, black).
"""
import sys
import numpy as np
from PIL import Image

RECT = {"xcb": (0, 88, 575, 650), "wayland": (0, 125, 580, 680)}


def stats(path, rect):
    a = np.asarray(Image.open(path).convert("RGB"))
    if a.shape[1] > 1400:
        a = a[:, : a.shape[1] // 2]
    x0, y0, x1, y1 = rect
    v = a[y0:y1, x0:x1].reshape(-1, 3)
    k = (v[:, 0].astype(int) << 16) | (v[:, 1].astype(int) << 8) | v[:, 2]
    u, c = np.unique(k, return_counts=True)
    return len(u), float((k != 0).mean()), "%06x" % u[c.argmax()], float(c.max() / len(k))


def main(argv):
    check = "--assert" in argv
    bad = 0
    for p in [x for x in argv if x != "--assert"]:
        route = "xcb" if "-xcb-" in p else "wayland"
        n, nonblack, common, share = stats(p, RECT[route])
        ok = n >= 1000 and nonblack >= 0.3
        print("%-40s colours=%-5d non-black=%.4f commonest=%s %.4f %s" % (p.split("/")[-1], n, nonblack, common, share, "DRAWS" if ok else "EMPTY"))
        if p.endswith("-3d.png") and not ok:
            bad = 1
    return bad if check else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
