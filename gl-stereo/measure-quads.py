#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later OR MIT
"""Measure per-colour centroid disparity in a full side-by-side image.

Expected pixel disparity for a quad at eye-space depth d:
    px = W_eye * (sep_pct/100) * (1 - Z/d)
where Z is the convergence distance.

Depths of the three quads are fixed by the tests at Z/2, Z and 2*Z
for the default convergence Z=5.  When the convergence is overridden,
the same geometry still lives at 2.5, 5.0 and 10.0 eye units; we
report the real depths in argv[4] if given.
"""

import sys
from PIL import Image
import numpy as np

THRESH = 32

def load_half(path):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    arr = np.array(im)
    left = arr[:, :w//2, :]
    right = arr[:, w//2:, :]
    return left, right, w//2, h

def centroid(mask):
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return float(np.mean(xs)), float(np.mean(ys))

def measure(left, right, w_eye):
    cols = [('red', np.array([255, 0, 0])),
            ('green', np.array([0, 255, 0])),
            ('blue', np.array([0, 0, 255]))]
    out = {}
    for name, c in cols:
        ml = np.all(np.abs(left.astype(int) - c) <= THRESH, axis=2)
        mr = np.all(np.abs(right.astype(int) - c) <= THRESH, axis=2)
        cl = centroid(ml)
        cr = centroid(mr)
        if cl is None or cr is None:
            out[name] = None
        else:
            out[name] = {'left': cl, 'right': cr, 'dx': cr[0] - cl[0]}
    out['nonblack_left'] = float(np.mean(np.any(left > 0, axis=2)))
    out['nonblack_right'] = float(np.mean(np.any(right > 0, axis=2)))
    out['w_eye'] = w_eye
    return out

def expected(sep_pct, Z, d, w_eye):
    return w_eye * (sep_pct / 100.0) * (1.0 - Z / d)

def main():
    if len(sys.argv) < 3:
        print("usage: measure-quads.py <ppm> <sep_pct> [Z] [depths: d1,d2,d3]", file=sys.stderr)
        sys.exit(1)
    path = sys.argv[1]
    sep_pct = float(sys.argv[2])
    Z = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
    depths = {'red': Z/2.0, 'green': Z, 'blue': Z*2.0}
    if len(sys.argv) > 4:
        ds = [float(x) for x in sys.argv[4].split(',')]
        depths = {'red': ds[0], 'green': ds[1], 'blue': ds[2]}
    left, right, w_eye, h = load_half(path)
    res = measure(left, right, w_eye)
    print(f"w_eye={w_eye} h={h} nonblack_left={res['nonblack_left']:.4f} nonblack_right={res['nonblack_right']:.4f}")
    ok = True
    for name in ('red', 'green', 'blue'):
        m = res[name]
        if m is None:
            print(f"{name}: MISSING", file=sys.stderr)
            ok = False
            continue
        exp = expected(sep_pct, Z, depths[name], w_eye)
        err = m['dx'] - exp
        status = 'PASS' if abs(err) <= 1.0 else 'FAIL'
        print(f"{name}: dx={m['dx']:.2f} expected={exp:.2f} err={err:.2f} [{status}]")
        if status == 'FAIL':
            ok = False
    if res['nonblack_left'] < 0.01 or res['nonblack_right'] < 0.01:
        print("empty half", file=sys.stderr)
        ok = False
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
