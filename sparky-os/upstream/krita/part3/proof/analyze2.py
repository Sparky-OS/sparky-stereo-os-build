#!/usr/bin/env python3
# usage: analyze2.py <base>   reads <base>.N.raw (RGBA16, bottom-up, as glReadPixels GL_UNSIGNED_SHORT) + .N.txt, per surface.
# Finds the full-range band (a long non-decreasing gray run spanning > 60000), takes its columns and height, and counts the distinct levels
# of the three bands below it (same columns, one band height further down each).
import sys, re, glob, numpy as np
def runs(row, minlen=300):
    d = np.diff(row); brk = np.where(d < 0)[0] + 1
    for a, b in zip(np.r_[0, brk], np.r_[brk, len(row)]):
        if b - a >= minlen: yield a, b
def run(b):
    meta = open(b + '.txt').read().strip(); print(meta)
    m = dict(re.findall(r'(\w+)=(-?\w+)', meta)); w, h = int(m['w']), int(m['h'])
    a = np.fromfile(b + '.raw', dtype=np.uint16).reshape(h, w, 4)[::-1].astype(np.int64)
    gray = (a[:, :, 0] == a[:, :, 1]) & (a[:, :, 1] == a[:, :, 2])
    full = []
    for y in range(h):
        if gray[y].mean() < 0.3: continue
        for s, e in runs(a[y, :, 1]):
            seg = a[y, s:e, 1]
            if seg.max() - seg.min() > 60000: full.append((y, s, e))
    if not full: print('  no full-range ramp found'); return
    s, e = max(((x[1], x[2]) for x in full), key=lambda t: sum(1 for x in full if (x[1], x[2]) == t))
    ys = [x[0] for x in full if (x[1], x[2]) == (s, e)]; y0, hb = min(ys), len(ys)
    names = ['full range 0..65535', '0.40..0.46', '1/256 of range (0.5000..0.5039)', '1/1024 of range (0.5000..0.5010)']
    for k in range(4):
        y = y0 + k * hb + hb // 2
        if y >= h: print('  band %d out of the canvas' % k); continue
        seg = a[y, s:e, 1]; print('  %-34s %d columns, span %5d/65535, DISTINCT LEVELS = %d' % (names[k], e - s, seg.max() - seg.min(), len(np.unique(seg))))
for tb in sorted(glob.glob(sys.argv[1] + '.[0-9].txt')):
    print('--- ' + tb); run(tb[:-4])
