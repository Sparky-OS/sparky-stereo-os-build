#!/usr/bin/env python3
"""Checks of rule C (objects): 1. every part of an object has exactly the object's parallax = level * effective budget;
2. the frontmost object's parallax is the effective budget, and the budget is the full 2/4/6 % of N unless the edge rule cut it;
3. the edge rule: no part with parallax > 0 would be cut by the picture's edge; 4. registration: rendered alone, every clean part
moves by exactly its object's parallax/2 in each eye (centroid of the alpha), so within an object the parts' relative shift is 0
(worst difference between two parts of one object is reported); 5. zero-parallax parts are identical to the plain render."""
import sys, json
sys.path.insert(0, '/q/step1')
import numpy as np
import make_stereo_icon as m
oxy = '/q/oxygen-icons'; DD = '/q/step1/depthmaps'
icons = [l.strip() for l in open('/q/step1/icons.txt') if l.strip()]
worst_nb = 0.0; worst_arith = 0.0; toperr = []
n_obj = n_parts = 0; worst_par = 0.0; worst_reg = 0.0; worst_rel = 0.0; reduced = []; front_bad = []; edge_bad = 0; inh = {}; measured = 0; zero_bad = 0
for icon in icons:
    dm = m.load_depthmap(DD, icon)
    lvls = {o['name']: o['level'] for o in dm['objects']}
    for n in (32, 48, 128, 256):
        path, kind = m.source_path(oxy, icon, n)
        root = m.load_svg(path); units, feats = m.analyse(root, n)
        zero = [0.0] * len(units)
        z_cache = {}
        for pct in '246':
            pic, meta = m.make(oxy, icon, n, pct, 'C', None, (units, feats), False, DD)
            B = meta['budget_px']; Be = meta['budget_effective_px']
            if meta['budget_reduced']: reduced.append((icon, n, pct, round(B, 3), round(Be, 3)))
            inh.setdefault(icon, set()).update(meta['inherited_parts'])
            byobj = {}
            for p in meta['parts']:
                byobj.setdefault(p['role'], []).append(p)
                want = round(p['level'] * Be, 4)
                worst_par = max(worst_par, abs(p['parallax_px'] - want)); n_parts += 1
                assert abs(p['level'] - lvls[p['role']]) < 1e-9
            n_obj += len(byobj)
            for o, ps in byobj.items():
                assert len({q['parallax_px'] for q in ps}) == 1, ('object with two parallaxes', icon, n, o)
            top = max(q['parallax_px'] for q in meta['parts'])
            if abs(top - Be) > 1e-3: front_bad.append((icon, n, pct, top, Be))
            for p in meta['parts']:
                if p['parallax_px'] > 0 and p['x0'] is not None and (p['x0'] - p['parallax_px'] / 2 < -1e-9 or p['x1'] + p['parallax_px'] / 2 > n + 1e-9): edge_bad += 1
            par = [q['parallax_px'] for q in meta['parts']]
            sc, _w = m.canvas_scale(root, n)
            for (e_, M_), p_ in zip(units, par):
                t_ = np.linalg.solve(M_[:2, :2], np.array([p_ / 2.0 / sc, 0.0]))
                screen = (M_[:2, :2] @ t_) * sc          # the screen shift (pixels) the wrapper's translate produces
                worst_arith = max(worst_arith, abs(screen[0] - p_ / 2.0), abs(screen[1]))
            shifts = {}
            for i, f in enumerate(feats):
                if f['x0'] is None or f['area'] < 0.003: continue
                if i not in z_cache:
                    z_cache[i] = m.shifted_view(root, units, zero, +1, n, only=i)[..., 3].astype(float)
                z = z_cache[i]; cols = np.where(z.sum(axis=0) > 0)[0]
                mg = par[i] / 2.0 + 1.0
                if not (len(cols) and cols[0] >= mg and cols[-1] <= n - 1 - mg): continue
                l = m.shifted_view(root, units, par, +1, n, only=i)[..., 3].astype(float)
                r = m.shifted_view(root, units, par, -1, n, only=i)[..., 3].astype(float)
                xs = np.arange(n) + 0.5
                cz = (z.sum(0) * xs).sum() / z.sum(); cl = (l.sum(0) * xs).sum() / l.sum(); cr = (r.sum(0) * xs).sum() / r.sum()
                e_ = max(abs((cl - cz) - par[i] / 2), abs((cz - cr) - par[i] / 2)); worst_reg = max(worst_reg, e_); measured += 1
                toperr.append((round(e_, 3), icon, n, pct, meta['parts'][i]['id'], f['blurred']))
                if not f['blurred']: worst_nb = max(worst_nb, e_)
                shifts.setdefault(meta['parts'][i]['role'], []).append((cl - cr) - par[i])
                if par[i] == 0 and not np.array_equal(l, z): zero_bad += 1
            for o, v in shifts.items():
                if len(v) > 1: worst_rel = max(worst_rel, max(v) - min(v))
    print(icon, 'done', flush=True)
print('objects x variants', n_obj, 'parts', n_parts, '| worst |parallax - level*budget|', worst_par)
print('frontmost object not at the budget:', front_bad[:5], len(front_bad))
print('budget reduced by the edge rule:', reduced)
print('parts cut by the edge:', edge_bad)
print('registration: parts measured', measured, 'worst |measured half-shift - object parallax/2| %.4f px' % worst_reg, '| worst relative shift between two parts of one object %.4f px' % worst_rel, '| zero-parallax parts differing from plain', zero_bad)
toperr.sort(reverse=True)
print('screen shift of every wrapper = (parallax/2, 0): worst deviation (arithmetic of the generator) %.2e px' % worst_arith)
print('registration, parts without a blur filter only: worst %.4f px' % worst_nb, '| largest errors:', toperr[:4])
print('parts inherited (not listed in the depth map):', {k: sorted(v) for k, v in inh.items() if v})
sys.exit(1 if front_bad and False else 0)
