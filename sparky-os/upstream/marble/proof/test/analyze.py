#!/usr/bin/env python3
"""Reads the stereo capture of the Marble probe (both eyes side by side, left first) and the probe's dump.

usage: analyze.py <capture.png> <probe.json> [out.txt]

* globe: points on the visible hemisphere, the right-minus-left disparity measured by block matching against the prediction of the orbit
  (the point seen by the left camera at pixel (u, v) has the left-frame coordinates (x, y, z) on the unit sphere; the right camera is the
  left one turned by -2h about the vertical axis, so d = R * (x*cos(2h) - z*sin(2h) - x))
* stars: the sky's stars, expected at the maximum parallax of the globe, 2 * R * sin(h) (the globe's far side)
* float items and the rest of the window: pixels that differ between the eyes
"""
import json
import math
import sys

import numpy as np
from PIL import Image


def gray(a):
    return a[..., :3].astype(np.float64) @ np.array([0.299, 0.587, 0.114])


def match(L, R, u, v, half, search, dys=(-1, 0, 1)):
    """best dx (sub-pixel) of the block around (u, v) of L in R, with uniqueness; returns (dx, dy, ratio) or None"""
    H, W = L.shape
    if v - half - 2 < 0 or v + half + 3 > H or u - half < 0 or u + half + 1 > W:
        return None
    blk = L[v - half:v + half + 1, u - half:u + half + 1]
    best = None
    for dy in dys:
        x0 = u - half - search
        x1 = u + half + 1 + search
        if x0 < 0 or x1 > W:
            return None
        strip = R[v + dy - half:v + dy + half + 1, x0:x1]
        win = np.lib.stride_tricks.sliding_window_view(strip, (2 * half + 1, 2 * half + 1))[0]
        sad = np.abs(win - blk[None]).sum(axis=(1, 2))  # one per dx in -search..search
        i = int(np.argmin(sad))
        if best is None or sad[i] < best[0]:
            best = (sad[i], dy, sad, i)
    sad0, dy, sad, i = best
    far = np.abs(np.arange(len(sad)) - i) >= 2
    second = sad[far].min() if far.any() else np.inf
    ratio = sad0 / second if second > 0 else 1.0
    frac = 0.0
    if 0 < i < len(sad) - 1:
        a, b, c = sad[i - 1], sad[i], sad[i + 1]
        den = a - 2 * b + c
        if den > 0:
            frac = 0.5 * (a - c) / den
    return (i - search + frac, dy, ratio)


RATIO=float(__import__('os').environ.get('RATIO','0.8'))

def main():
    cap, probe = sys.argv[1], sys.argv[2]
    out = open(sys.argv[3], 'w') if len(sys.argv) > 3 else sys.stdout

    def say(*a):
        print(*a, file=out)
        print(*a)

    p = json.load(open(probe))
    img = np.array(Image.open(cap).convert('RGBA'))
    H, W2 = img.shape[:2]
    W = W2 // 2
    wx, wy, ww, wh = p['widget']
    say(f"capture {W2}x{H} (eye {W}x{H}), probe: platform={p['platform']} stereo3D={p['stereo3D']} separation={p['separation_deg']} deg radius={p['radius']} widget={p['widget']}")
    Lc, Rc = img[:, :W], img[:, W:]
    L, R = gray(Lc), gray(Rc)
    cx, cy, rad = wx + ww / 2.0, wy + wh / 2.0, float(p['radius'])
    h = math.radians(p['separation_deg']) / 2
    items = [(it['name'], it['rect']) for it in p['float_items']]
    # ---- the globe
    half = 8
    pred_max = 2 * rad * math.sin(2 * h)  # bound of |d| on the sphere
    search = int(math.ceil(pred_max)) + 6
    samples = []
    step = 5
    for v in range(int(cy - 0.88 * rad), int(cy + 0.88 * rad), step):
        for u in range(int(cx - 0.88 * rad), int(cx + 0.88 * rad), step):
            x, y = (u - cx) / rad, -(v - cy) / rad
            if x * x + y * y > 0.80:
                continue
            if any(r[0] - 12 <= u <= r[0] + r[2] + 12 and r[1] - 12 <= v <= r[1] + r[3] + 12 for _, r in items):
                continue
            blk = L[v - half:v + half + 1, u - half:u + half + 1]
            if blk.shape != (2 * half + 1, 2 * half + 1) or blk.std() < 4.0:
                continue
            samples.append((blk.std(), u, v))
    samples.sort(reverse=True)
    errs, meas, preds, dys, used = [], [], [], [], 0
    for _, u, v in samples[:1500]:
        m = match(L, R, u, v, half, search)
        if m is None:
            continue
        dx, dy, ratio = m
        if ratio > RATIO:
            continue
        x, y = (u - cx) / rad, -(v - cy) / rad
        z = math.sqrt(max(0.0, 1 - x * x - y * y))
        pred = rad * (x * math.cos(2 * h) - z * math.sin(2 * h) - x)
        errs.append(dx - pred)
        meas.append(dx)
        preds.append(pred)
        dys.append(dy)
        used += 1
    errs = np.array(errs)
    if used:
        say(f"globe: {used} points on the visible hemisphere (of {len(samples)} candidates); predicted right-minus-left disparity {min(preds):.2f}..{max(preds):.2f} px")
        say(f"globe: measured minus predicted: median {np.median(errs):+.2f} px, median |error| {np.median(np.abs(errs)):.2f} px, within 1 px: {100 * np.mean(np.abs(errs) <= 1):.0f} %, within 0.5 px: {100 * np.mean(np.abs(errs) <= 0.5):.0f} %")
        near = np.array(preds) < -0.5 * abs(min(preds))
        far = np.array(preds) > 0.5 * abs(max(preds))
        mm, pp = np.array(meas), np.array(preds)
        if near.any():
            say(f"globe: near side (pred < half of the maximum, {near.sum()} points): predicted mean {pp[near].mean():+.2f} px, measured mean {mm[near].mean():+.2f} px")
        if far.any():
            say(f"globe: far side ({far.sum()} points): predicted mean {pp[far].mean():+.2f} px, measured mean {mm[far].mean():+.2f} px")
        say(f"globe: correlation measured/predicted {np.corrcoef(mm, pp)[0, 1]:.3f}; best vertical shift dy=0 for {100 * np.mean(np.array(dys) == 0):.0f} % of the points")
    else:
        say("globe: no points matched")
    # ---- the stars
    sky = []
    for v in range(8, H - 8):
        row = L[v]
        for u in np.nonzero(row > 60)[0]:
            if u < 12 or u >= W - 12:
                continue
            x, y = (u - cx) / rad, -(v - cy) / rad
            if x * x + y * y < 1.15 ** 2:
                continue
            if wx <= u < wx + ww and wy <= v < wy + wh:
                if any(r[0] - 14 <= u <= r[0] + r[2] + 14 and r[1] - 14 <= v <= r[1] + r[3] + 14 for _, r in items):
                    continue
                if L[v, u] >= L[v - 1:v + 2, u - 1:u + 2].max():
                    ring = L[v - 5:v + 6, u - 5:u + 6].copy()
                    ring[3:8, 3:8] = 0
                    # an isolated bright point: a star, not a line or a label of the sky
                    if L[v, u] > 100 and ring.max() < 0.35 * L[v, u]:
                        sky.append((L[v, u], u, v))
    sky.sort(reverse=True)
    pm = 2 * rad * math.sin(h)
    sm = []
    for _, u, v in sky[:400]:
        m = match(L, R, u, v, 4, int(math.ceil(pm)) + 10, dys=(0,))
        if m is None or m[2] > 0.7:
            continue
        sm.append(m[0])
    if sm:
        sm = np.array(sm)
        say(f"stars: {len(sm)} stars matched (of {len(sky)} found); predicted maximum parallax 2*R*sin(h) = {pm:.2f} px; measured median {np.median(sm):+.2f} px, mean {sm.mean():+.2f} px, within 1 px of the prediction: {100 * np.mean(np.abs(sm - pm) <= 1):.0f} %")
    else:
        say(f"stars: none matched ({len(sky)} found)")
    # ---- 2D parts: pixels that differ between the eyes
    diff = np.any(Lc != Rc, axis=2)
    say(f"whole screen: {int(diff.sum())} of {W * H} pixels differ between the eyes")
    mask = np.zeros((H, W), bool)
    mask[wy:wy + wh, wx:wx + ww] = True
    say(f"outside the map widget (menu bar, status bar, window background): {int(diff[~mask].sum())} differing pixels of {int((~mask).sum())}")
    for name, r in items:
        x0, y0, x1, y1 = int(r[0]), int(r[1]), int(math.ceil(r[0] + r[2])), int(math.ceil(r[1] + r[3]))
        sub = diff[y0:y1, x0:x1]
        say(f"float item {name}: rectangle {x0},{y0} {x1 - x0}x{y1 - y0}: {int(sub.sum())} differing pixels of {sub.size}")
    say(f"summary: globe n={used} median_abs_err={np.median(np.abs(errs)) if used else float('nan'):.2f}")


main()
