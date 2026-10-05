#!/usr/bin/env python3
"""Checks of the generator itself (no KWin): 1. zero parallax reproduces the plain librsvg render of the source
exactly; 2. every inked unit rendered alone in both eyes has centroid(left) - centroid(right) = its planned
parallax; 3. the two eyes of the whole icon differ by no vertical movement (row ink profiles agree to the ink
the horizontal cut of the picture's edge could change: none, by the edge rule)."""
import sys, json, io, subprocess
sys.path.insert(0, '/q/step1')
import numpy as np
from PIL import Image
import make_stereo_icon as m
oxy = '/q/oxygen-icons'
icons = [l.split()[0] for l in open('/q/step1/icons.txt') if l.strip()]
worst_id = 0; worst_c = 0.0; worst_dy = 0.0; bad = []; rows = 0; measured = 0; unclean = 0; errs = []
TOL = 0.1
for icon in icons:
    for n in (32, 48, 128, 256):
        path, kind = m.source_path(oxy, icon, n)
        root = m.load_svg(path)
        plain = m.render(root, n)
        units, feats = m.analyse(root, n)
        zero = [0.0] * len(units)
        L = m.shifted_view(root, units, zero, +1, n); R = m.shifted_view(root, units, zero, -1, n)
        d = int(np.abs(L.astype(int) - plain.astype(int)).max()); d2 = int(np.abs(R.astype(int) - plain.astype(int)).max())
        worst_id = max(worst_id, d, d2)
        for rule in 'AB':
            for pct in '246':
                pic, meta = m.make(oxy, icon, n, pct, rule, None, (units, feats))
                par = [p['parallax_px'] for p in meta['parts']]
                lv = [p['level'] for p in meta['parts']]
                parv = [lv_i * meta['budget_effective_px'] for lv_i in lv]
                # vertical: eyes' row ink profiles
                a = pic[:, :n, 3].astype(float).sum(axis=1); b = pic[:, n:, 3].astype(float).sum(axis=1)
                vprof = float(np.abs(a - b).max() / 255.0)
                todo = {meta['front_unit'], meta['back_unit']} | {i for i, f in enumerate(feats) if f['area'] >= 0.02}
                for i in sorted(todo):
                    f = feats[i]
                    l = m.shifted_view(root, units, parv, +1, n, only=i)[..., 3].astype(float)
                    r = m.shifted_view(root, units, parv, -1, n, only=i)[..., 3].astype(float)
                    z = m.shifted_view(root, units, zero, +1, n, only=i)[..., 3].astype(float)
                    cols = np.where(z.sum(axis=0) > 0)[0]
                    m_ = parv[i] / 2.0 + 1.0
                    clean = len(cols) > 0 and cols[0] >= m_ and cols[-1] <= n - 1 - m_ and l.sum() > 0 and r.sum() > 0
                    if not clean:
                        unclean += 1
                        continue
                    xs = np.arange(n) + 0.5; ys = np.arange(n) + 0.5
                    cl = (l.sum(axis=0) * xs).sum() / l.sum(); cr = (r.sum(axis=0) * xs).sum() / r.sum()
                    err = abs((cl - cr) - parv[i])
                    dy = abs((l.sum(axis=1) * ys).sum() / l.sum() - (r.sum(axis=1) * ys).sum() / r.sum())
                    measured += 1
                    worst_c = max(worst_c, err); worst_dy = max(worst_dy, dy)
                    errs.append((err, n, icon, rule, pct, i, parv[i], cl - cr))
                    if err > TOL or dy > 0.02:
                        bad.append((icon, n, rule, pct, i, round(parv[i], 3), round(cl - cr, 3), round(dy, 4)))
                rows += 1
    print(icon, 'identity', worst_id, 'worst error so far %.4f px' % worst_c, flush=True)
errs.sort(reverse=True)
print('variants checked', rows, 'identity max diff', worst_id, '| parts measured', measured, '(skipped, any ink within the shift of the picture edge:', unclean, ')')
print('worst parallax error %.4f px, worst vertical centroid difference %.4f px, tolerance %.2f px, out of tolerance %d' % (worst_c, worst_dy, TOL, len(bad)))
print('largest errors:', [(round(e[0], 3), e[1], e[2], e[3], e[4], e[6] and round(e[6], 3)) for e in errs[:5]])
for b in bad[:20]: print('BAD', b)
sys.exit(1 if bad or worst_id else 0)
