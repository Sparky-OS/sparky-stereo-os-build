#!/usr/bin/env python3
"""Read a KWin stereo window capture (full side by side, left eye first) and say what each eye shows.

For each half: pixel counts by colour class (red, green, blue, white, black, other), the row
bands where red or green dominates, the mean colour of the inner area, and whether the top rows
(a 2D decoration or menu bar) are identical in both eyes. Exit 0 always; the numbers are the result.
"""
import sys
import numpy as np
from PIL import Image


def classify(rgb):
    r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
    red = (r > 180) & (g < 80) & (b < 80)
    green = (g > 180) & (r < 80) & (b < 80)
    blue = (b > 180) & (r < 80) & (g < 80)
    white = (r > 200) & (g > 200) & (b > 200)
    black = (r < 30) & (g < 30) & (b < 30)
    other = ~(red | green | blue | white | black)
    return dict(red=red, green=green, blue=blue, white=white, black=black, other=other)


def bands(mask, label):
    rows = np.where(mask.mean(axis=1) > 0.5)[0]
    if len(rows) == 0:
        return f"{label}: no row dominated"
    # contiguous runs
    runs = []
    start = prev = rows[0]
    for r in rows[1:]:
        if r != prev + 1:
            runs.append((start, prev))
            start = r
        prev = r
    runs.append((start, prev))
    return f"{label} rows: " + ", ".join(f"{a}..{b}" for a, b in runs)


def describe(name, half):
    h, w = half.shape[:2]
    cls = classify(half)
    n = h * w
    counts = ", ".join(f"{k}={int(v.sum())}" for k, v in cls.items())
    inner = half[h // 4: 3 * h // 4, w // 4: 3 * w // 4]
    mean = inner.reshape(-1, 3).mean(axis=0)
    print(f"{name}: {w}x{h} px={n} {counts}")
    print(f"  inner mean R{mean[0]:.0f} G{mean[1]:.0f} B{mean[2]:.0f}")
    print("  " + bands(cls["red"], "red"))
    print("  " + bands(cls["green"], "green"))
    return cls


def main(path):
    img = np.asarray(Image.open(path).convert("RGB"))
    h, w = img.shape[:2]
    print(f"capture {w}x{h}")
    if w % 2:
        print("odd width: not a packed stereo capture")
    half = w // 2
    left, right = img[:, :half], img[:, half:2 * half]
    describe("left eye", left)
    describe("right eye", right)
    diff = np.any(left != right, axis=2)
    print(f"pixels differing between eyes: {int(diff.sum())} of {half * h} ({diff.mean():.4f})")
    top = min(28, h)
    same_top = np.all(left[:top] == right[:top])
    frac_top = float(np.all(left[:top] == right[:top], axis=2).mean()) if top else 1.0
    print(f"top {top} rows identical in both eyes: {same_top} ({frac_top:.4f} of pixels)")
    # verdict helpers
    lc, rc = classify(left), classify(right)
    ln, rn = half * h, half * h
    print(f"left red share {lc['red'].sum() / ln:.3f} green share {lc['green'].sum() / ln:.3f}; "
          f"right red share {rc['red'].sum() / rn:.3f} green share {rc['green'].sum() / rn:.3f}")


if __name__ == "__main__":
    main(sys.argv[1])
