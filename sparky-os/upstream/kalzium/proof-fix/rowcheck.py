"""Vertical check independent of the block size: the molecule's row profile (non-black pixels per row, summed brightness per row) in the viewer must be the same in both eyes if there is no vertical disparity. usage: rowcheck.py <case-dir>"""
import sys, numpy as np
from PIL import Image
img = np.array(Image.open(f"{sys.argv[1]}/window.png").convert("RGB")).astype(float)
H, W2, _ = img.shape; W = W2 // 2
L, R = img[:, :W], img[:, W:]
x0, x1, y0, y1 = 302, 542, 57, 314
l = L[y0:y1, x0:x1].sum(axis=2); r = R[y0:y1, x0:x1].sum(axis=2)
pl, pr = l.sum(axis=1), r.sum(axis=1)
best = min(range(-4, 5), key=lambda d: np.abs(np.roll(pl, d) - pr).sum())
rows = np.nonzero(pl > 0)[0]; rows_r = np.nonzero(pr > 0)[0]
print(f"{sys.argv[1]}: molecule rows left {rows.min()+y0}..{rows.max()+y0}, right {rows_r.min()+y0}..{rows_r.max()+y0}; best vertical shift of the row profile {best}; max abs row-profile difference {np.abs(pl-pr).max():.0f} of {pl.max():.0f}")
