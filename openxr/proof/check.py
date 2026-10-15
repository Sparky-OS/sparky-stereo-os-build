#!/usr/bin/env python3
# Reads a Stereo KWin capture (both eyes side by side, left eye first) and checks the spectator
# window: a rectangle where the left eye shows the client's red view and the right eye its blue
# view; inside it only pixels identical in both eyes may break the pattern (Monado's own 2D window
# lies on top, identical in both eyes); outside it 0 pixels differ between the eyes.
# usage: check.py capture.png expected_w expected_h [before.png]
import sys
import numpy as np
from PIL import Image

cap = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
ew, eh = int(sys.argv[2]), int(sys.argv[3])
h, w, _ = cap.shape
left, right = cap[:, : w // 2], cap[:, w // 2 :]
print(f"capture {w}x{h}: eyes {w // 2}x{h}")
fails = []

red_l = (left[:, :, 0] > 150) & (left[:, :, 1] < 60) & (left[:, :, 2] < 60)
blue_r = (right[:, :, 2] > 150) & (right[:, :, 0] < 60) & (right[:, :, 1] < 60)
stereo = red_l & blue_r
same = np.abs(left - right).sum(axis=2) <= 24
ys, xs = np.nonzero(stereo)
if len(xs) == 0:
    fails.append("no pixel shows red in the left eye and blue in the right eye")
else:
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    print(f"spectator rectangle: x {x0}..{x1} y {y0}..{y1} = {x1 - x0}x{y1 - y0} (expected {ew}x{eh})")
    if (x1 - x0, y1 - y0) != (ew, eh):
        fails.append("the spectator rectangle has not the expected size")
    inside = stereo[y0:y1, x0:x1] | same[y0:y1, x0:x1]
    bad = int((~inside).sum())
    print(f"inside it: {int(stereo[y0:y1, x0:x1].sum())} LEFT/RIGHT pixels, {int(same[y0:y1, x0:x1].sum())} identical (2D on top), {bad} other")
    if bad:
        fails.append("pixels inside the rectangle are neither the eye pair nor 2D")
    blue_l = (left[:, :, 2] > 150) & (left[:, :, 0] < 60)
    red_r = (right[:, :, 0] > 150) & (right[:, :, 2] < 60)
    swapped = int((blue_l & red_r).sum())
    print(f"swapped-eye pixels (blue left, red right): {swapped}")
    if swapped:
        fails.append("some pixels show the eyes swapped")
    mask = np.ones(same.shape, bool)
    mask[y0:y1, x0:x1] = False
    outside = int(((~same) & mask).sum())
    print(f"differing pixels outside the rectangle: {outside}")
    if outside:
        fails.append("pixels outside the spectator rectangle differ between the eyes")

if len(sys.argv) > 4:
    before = np.asarray(Image.open(sys.argv[4]).convert("RGB")).astype(int)
    bw = before.shape[1]
    bdiff = int((np.abs(before[:, : bw // 2] - before[:, bw // 2 :]).sum(axis=2) > 24).sum())
    print(f"before the client ran: {before.shape[1]}x{before.shape[0]}, {bdiff} differing pixels between the halves")

for f in fails:
    print("FAIL:", f)
print("PASS" if not fails else "FAILED")
sys.exit(1 if fails else 0)
