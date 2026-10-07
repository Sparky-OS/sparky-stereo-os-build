#!/usr/bin/env python3
"""Reads the stereo capture of the Marble probe (both eyes side by side, left first) and the probe's dump.

usage: analyze.py <capture.png> <probe.json> [out.txt]

* globe: points on the visible hemisphere, the right-minus-left disparity measured by block matching against the prediction of the orbit
  (perspective: the point the left eye camera sees at pixel (u, v) is found by the ray through the pixel and the unit sphere, then projected
  by the right eye camera: parallel axes, off-axis, zero parallax on the plane through the globe center)
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
    Rad = float(p['radius'])
    P = 1.5 + 3 * 1000 * 0.4 / Rad / math.tan(0.5 * 110 * math.pi / 180)
    sc = Rad * math.sqrt((P + 1) / (P - 1))   # pixels per globe radius on the plane through the globe's centre
    e = P * math.sin(h)                      # the camera's offset (globe radii): +e right eye, -e left eye

    def surface(u, v, eye):
        """the point of the unit sphere the eye camera sees at pixel (u, v): X right, Y up, Z to the viewer; None off the globe"""
        xu, yu = (u + 0.5 - cx) / sc, -(v + 0.5 - cy) / sc
        a = (xu - eye * (P - 1) / P) / (P - 1)
        b = yu / (P - 1)
        qa, qb = a * a + b * b + 1, eye * a - P
        disc = qb * qb - qa * (eye * eye + P * P - 1)
        if disc < 0:
            return None
        dd = (-qb - math.sqrt(disc)) / qa
        return eye + a * dd, b * dd, P - dd

    def project(X, Y, Z, eye):
        return cx + sc * ((P - 1) * (X - eye) / (P - Z) + eye * (P - 1) / P), cy - sc * (P - 1) * Y / (P - Z)

    half = 8
    pred_max = 2 * sc * (P - 1) * math.sin(h) + 4
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
    errs, meas, preds, dys, used, zs = [], [], [], [], 0, []
    for _, u, v in samples[:1500]:
        m = match(L, R, u, v, half, search)
        if m is None:
            continue
        dx, dy, ratio = m
        if ratio > RATIO:
            continue
        pt = surface(u, v, -e)
        if pt is None:
            continue
        xr, yr = project(*pt, e)
        pred = xr - (u + 0.5)
        errs.append(dx - pred)
        meas.append(dx)
        preds.append(pred)
        zs.append(pt[2])
        dys.append(dy)
        used += 1
    errs = np.array(errs)
    if used:
        mm, pp, zz = np.array(meas), np.array(preds), np.array(zs)
        say(f"globe: P={P:.3f} (camera distance in globe radii), eye offset e={e:.4f}, {used} points on the visible hemisphere (of {len(samples)} candidates); predicted right-minus-left disparity {pp.min():.2f}..{pp.max():.2f} px")
        say(f"globe: measured minus predicted: median {np.median(errs):+.2f} px, median |error| {np.median(np.abs(errs)):.2f} px, within 1 px: {100 * np.mean(np.abs(errs) <= 1):.0f} %, within 0.5 px: {100 * np.mean(np.abs(errs) <= 0.5):.0f} %")
        nr = zz > 0.7
        fr = zz < 0.4
        say(f"globe: sign: measured disparity negative (crossed: the surface is in front of the zero-parallax plane through the globe's center) for {100 * np.mean(mm < 0):.0f} % of the points, predicted {100 * np.mean(pp < 0):.0f} %")
        if nr.any():
            say(f"globe: near surface (Z>0.7, {int(nr.sum())} points): predicted mean {pp[nr].mean():+.2f} px, measured mean {mm[nr].mean():+.2f} px")
        if fr.any():
            say(f"globe: toward the limb (Z<0.4, {int(fr.sum())} points): predicted mean {pp[fr].mean():+.2f} px, measured mean {mm[fr].mean():+.2f} px")
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
    pm = 2 * sc * (P - 1) * math.sin(h)   # a point at infinity: the camera offsets taken to the plane through the globe's center
    sm = []
    for _, u, v in sky[:400]:
        m = match(L, R, u, v, 4, int(math.ceil(pm)) + 10, dys=(0,))
        if m is None or m[2] > 0.7:
            continue
        sm.append(m[0])
    if sm:
        sm = np.array(sm)
        say(f"stars: {len(sm)} stars matched (of {len(sky)} found); predicted parallax at infinity 2*s*(P-1)*sin(h) = {pm:.2f} px; measured median {np.median(sm):+.2f} px, mean {sm.mean():+.2f} px, within 1 px of the prediction: {100 * np.mean(np.abs(sm - pm) <= 1):.0f} %")
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
