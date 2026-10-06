#!/usr/bin/env python3
# usage: analyze.py <base>   reads <base>.N.raw (RGBA16 bottom-up, as glReadPixels GL_UNSIGNED_SHORT) + .N.txt, per surface.
# Finds the two ramps (full range 0..65535 and narrow 0.40..0.46) as long non-decreasing gray runs and counts the distinct levels in them.
import sys, re, glob, numpy as np
def runs(row, minlen=300):
    # maximal non-decreasing runs of the row (gray ramp pixels), allowing equal neighbours
    d = np.diff(row); brk = np.where(d < 0)[0] + 1
    for a, b in zip(np.r_[0, brk], np.r_[brk, len(row)]):
        if b - a >= minlen: yield a, b
def run(b):
    meta = open(b + '.txt').read().strip(); print(meta)
    m = dict(re.findall(r'(\w+)=(-?\w+)', meta)); w, h = int(m['w']), int(m['h'])
    a = np.fromfile(b + '.raw', dtype=np.uint16).reshape(h, w, 4)[::-1].astype(np.int64)
    gray = (a[:, :, 0] == a[:, :, 1]) & (a[:, :, 1] == a[:, :, 2])
    found = {'full': None, 'narrow': None}
    for y in range(h):
        if gray[y].mean() < 0.5: continue
        for s, e in runs(a[y, :, 1]):
            seg = a[y, s:e, 1]; span = int(seg.max() - seg.min()); n = len(np.unique(seg))
            if span > 60000: kind = 'full'
            else: continue
            if found[kind] is None or n > found[kind][3]: found[kind] = (y, e - s, span, n)
    # the narrow ramp: same columns as the full ramp's run, rows below it, any row whose span there is the narrow range
    if found['full'] and not found['narrow']:
        y0, ln, _, _ = found['full']
        row = a[y0, :, 1]
        for s0, e0 in runs(row):
            if row[s0:e0].max() - row[s0:e0].min() > 60000: break
        best = None
        for y in range(y0, h):
            seg = a[y, s0:e0, 1]; span = int(seg.max() - seg.min())
            if 2500 < span < 7000 and gray[y, s0:e0].all():
                n = len(np.unique(seg))
                if best is None or n > best[3]: best = (y, e0 - s0, span, n)
        found['narrow'] = best
    for kind, label in (('full', 'full-range ramp (0..65535)'), ('narrow', 'narrow ramp (0.40..0.46)')):
        f = found[kind]
        print('  %s: %s' % (label, 'not found' if not f else 'row %d, %d columns, span %d/65535, DISTINCT LEVELS = %d' % f))
for tb in sorted(glob.glob(sys.argv[1] + '.[0-9].txt')):
    print('--- ' + tb); run(tb[:-4])
