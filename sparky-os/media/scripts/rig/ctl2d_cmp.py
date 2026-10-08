#!/usr/bin/env python3
# usage: ctl2d_cmp.py <prefix>   compares the captures of runs/<prefix>-<vo>-<dither>-<dmo|ours>-<rep>/c00.png
# pairs: same build against itself (the noise), dmo against ours (the control): number of differing pixels and the largest difference
import sys, glob, itertools, os, numpy as np
from PIL import Image
pre = sys.argv[1]
runs = {}
for d in sorted(glob.glob('runs/%s-*' % pre)):
    p = d + '/c00.png'
    if not os.path.exists(p): print('MISSING', p); continue
    nm = os.path.basename(d)[len(pre) + 1:]
    vo, dv, b, rep = nm.rsplit('-', 3)
    runs.setdefault((vo, dv), {}).setdefault(b, []).append((rep, np.array(Image.open(p).convert('RGB')).astype(int)))
tot = {'noise': 0, 'ctl': 0}
for k, v in sorted(runs.items()):
    def cmp(a, b):
        if a.shape != b.shape: return ('shape %s vs %s' % (a.shape, b.shape), -1, -1)
        dd = np.abs(a - b).max(axis=2); return ('', int((dd > 0).sum()), int(dd.max()))
    for b in ('dmo', 'ours'):
        for (r1, a), (r2, c) in itertools.combinations(v.get(b, []), 2):
            m, n, mx = cmp(a, c); print('%s %s noise %s run%s/run%s: %d differing pixels, max %d %s' % (k[0], k[1], b, r1, r2, n, mx, m))
    for (r1, a), (r2, c) in itertools.product(v.get('dmo', []), v.get('ours', [])):
        m, n, mx = cmp(a, c); tot['ctl'] += max(n, 0)
        print('%s %s CONTROL dmo run%s / ours run%s: %d differing pixels, max %d %s' % (k[0], k[1], r1, r2, n, mx, m))
print('total differing pixels over all dmo/ours pairs:', tot['ctl'])
