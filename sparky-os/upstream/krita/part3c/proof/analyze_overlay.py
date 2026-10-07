#!/usr/bin/env python3
"""analyze_overlay.py <screen without overlay.png> <screen with overlay.png>   two KWin stereo screen captures (full side by side, left eye first)
of the same session, the second with a 2D overlay (Krita's popup palette) opened over the stereo canvas. For each eye: the pixels the overlay changed.
Reports whether the overlay covers the same pixels in both eyes (it is on the screen plane) and how many changed pixels are not identical in both eyes."""
import sys, numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int)
b = np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(int)
W = a.shape[1] // 2
chL = (a[:, :W] != b[:, :W]).any(axis=2)
chR = (a[:, W:] != b[:, W:]).any(axis=2)
print('screen %dx%d, one eye %dx%d' % (a.shape[1], a.shape[0], W, a.shape[0]))
print('pixels changed by the overlay: left eye %d, right eye %d' % (chL.sum(), chR.sum()))
print('changed in one eye only: %d' % (chL ^ chR).sum())
both = chL & chR
same = (b[:, :W][both] == b[:, W:][both]).all(axis=1)
print('changed in both eyes: %d, of them identical in the two eyes: %d (the rest is the overlay blended over the two different views)' % (both.sum(), same.sum()))
ys, xs = np.where(chL | chR)
if len(ys): print('bbox of the overlay: x %d..%d y %d..%d' % (xs.min(), xs.max(), ys.min(), ys.max()))
