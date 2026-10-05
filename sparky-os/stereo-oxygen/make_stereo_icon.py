#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-3.0-or-later
"""Stereo Oxygen generator: one Oxygen source drawing -> one PNG holding the two views side by side
(left eye first, 2N x N).

One world, two cameras: the drawing's parts ("units") are placed at depths; the left eye sees each unit shifted
horizontally by +parallax/2 and the right eye by -parallax/2, around the original picture (a popped unit is
seen further right by the left eye, as in any stereo pair). Nothing is warped, nothing is redrawn: each unit is
wrapped in a <g transform="translate(...)"> and the shifted drawing is rendered by librsvg (sub-pixel shifts
come out of the vector drawing).

Source rule (the study's rule 1.2, without hidef): scalable/<context>/small/<N>x<N>/<name> when it exists,
else scalable/<context>/<name>.

UNITS (the "parts"), in paint order. Starting at the document root:
  * a child that is a <g> of Inkscape groupmode "layer" is entered (its children are units), unless it is
    display:none (skipped);
  * a non-layer <g> with no filter, mask, clip-path or opacity of its own that is the only drawable child of its
    container is entered too (a lone wrapper);
  * every other drawable child (path, rect, circle, ellipse, polygon, polyline, line, text, use, image, and any
    other <g>) is one unit; a <g> is never split, so an object drawn as a group moves as a whole.

DEPTH. B = strength * N is the total parallax (pixels) between the icon's back (level 0, parallax 0, the
icon's own level) and its front (parallax B). Parallax is never negative: nothing goes behind the icon's level.
  Rule A (paint order): unit i of n (0 = first painted) has parallax B * i / (n-1); the first unit is at the icon's
    level, the last painted unit at B, the others evenly between.
  Rule B (role guessed from structure), per unit, from its isolated rendering at N x N (alpha-weighted luma Y
    of the straight colour, mean alpha over pixels with alpha > 0.04, area = sum(alpha)/N^2) and from the XML
    (blurred = the unit or a descendant uses a filter containing feGaussianBlur with stdDeviation > 0):
      1. unit 0 (the lowest) -> level 0
      2. shadow: Y <= 0.25 and (blurred or mean alpha < 0.85)          -> level 0
      3. highlight/glow: not a shadow, Y >= 0.75 and area <= 0.12      -> level 1.0
      4. everything else (the body)                                     -> level 0.5
    parallax = level * B. The first matching line wins.
  Rule C (objects, by hand): depthmaps/<context>/<name>.json lists the icon's objects, each with a level from 0 (the icon's
    own level) to 1 (the most popped) and the ids of the drawing's parts that belong to it. Every part of one object gets the
    same parallax, level * B, so a surface, its outline, its shading and its highlights never separate; the icon's cast
    shadow is an object at level 0. A part that no object lists (the small drawings carry a few extra ids) takes the object
    of the nearest listed part before it in paint order (else the first one after it); the metadata lists these parts.
EDGES. The ink of a unit is the set of columns where some pixel of its isolated rendering has alpha >= 16/255,
extent [x0, x1) in pixels. A unit at parallax p is seen shifted by p/2 either way, so it needs x0 - p/2 >= 0
and x1 + p/2 <= N. If a rule/strength would cut a unit at the picture's edge, the icon's budget B is reduced to
the largest value where nothing is cut (B_eff) and the metadata says so.
"""
import argparse, copy, gzip, io, json, math, os, re, subprocess, sys
import numpy as np
from lxml import etree
from PIL import Image

SVG = 'http://www.w3.org/2000/svg'
INK = 'http://www.inkscape.org/namespaces/inkscape'
XL = 'http://www.w3.org/1999/xlink'
DRAW = {'path', 'rect', 'circle', 'ellipse', 'polygon', 'polyline', 'line', 'text', 'use', 'image'}
SKIP = {'defs', 'metadata', 'namedview', 'title', 'desc', 'style', 'script'}
STRENGTHS = {'2': 0.02, '4': 0.04, '6': 0.06}


def ln(e):
    t = e.tag
    return t.rsplit('}', 1)[-1] if isinstance(t, str) else ''


def load_svg(path):
    b = open(path, 'rb').read()
    if b[:2] == b'\x1f\x8b':
        b = gzip.decompress(b)
    return etree.fromstring(b)


def source_path(oxy, icon, n):
    ctx, name = icon.split('/')
    for p in (f'{oxy}/scalable/{ctx}/small/{n}x{n}/{name}.svgz', f'{oxy}/scalable/{ctx}/small/{n}x{n}/{name}.svg',
              f'{oxy}/scalable/{ctx}/{name}.svgz', f'{oxy}/scalable/{ctx}/{name}.svg'):
        if os.path.exists(p):
            return p, ('small/%dx%d' % (n, n)) if '/small/' in p else 'base'
    raise FileNotFoundError(icon)


# ---- transforms -------------------------------------------------------------------------------------------
NUM = r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?'


def parse_transform(s):
    m = np.eye(3)
    if not s:
        return m
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', s):
        a = [float(x) for x in re.findall(NUM, args)]
        t = np.eye(3)
        if name == 'matrix':
            t = np.array([[a[0], a[2], a[4]], [a[1], a[3], a[5]], [0, 0, 1]])
        elif name == 'translate':
            t[0, 2], t[1, 2] = a[0], (a[1] if len(a) > 1 else 0)
        elif name == 'scale':
            t[0, 0], t[1, 1] = a[0], (a[1] if len(a) > 1 else a[0])
        elif name == 'rotate':
            c, sn = math.cos(math.radians(a[0])), math.sin(math.radians(a[0]))
            r = np.array([[c, -sn, 0], [sn, c, 0], [0, 0, 1]])
            if len(a) == 3:
                t = np.array([[1, 0, a[1]], [0, 1, a[2]], [0, 0, 1]]) @ r @ np.array([[1, 0, -a[1]], [0, 1, -a[2]], [0, 0, 1]])
            else:
                t = r
        elif name == 'skewX':
            t[0, 1] = math.tan(math.radians(a[0]))
        elif name == 'skewY':
            t[1, 0] = math.tan(math.radians(a[0]))
        m = m @ t
    return m


def style_of(e):
    d = {}
    for part in (e.get('style') or '').split(';'):
        if ':' in part:
            k, v = part.split(':', 1)
            d[k.strip()] = v.strip()
    return d


def prop(e, k):
    return style_of(e).get(k, e.get(k))


def hidden(e):
    return prop(e, 'display') == 'none'


def atomic_style(e):
    """a group that cannot be entered without changing the picture"""
    for k in ('filter', 'mask', 'clip-path'):
        v = prop(e, k)
        if v and v != 'none':
            return True
    op = prop(e, 'opacity')
    return op is not None and op not in ('1', '1.0') and float(re.findall(NUM, op)[0]) < 1


def find_units(root):
    """[(element, parent matrix as 3x3)] in paint order"""
    units = []

    def drawable(e):
        return isinstance(e.tag, str) and ln(e) not in SKIP and not ln(e).startswith('namedview') and not hidden(e) \
            and (ln(e) in DRAW or ln(e) == 'g')

    def walk(container, m):
        kids = [c for c in container if drawable(c)]
        for c in kids:
            t = ln(c)
            if t == 'g':
                layer = c.get('{%s}groupmode' % INK) == 'layer'
                lone = len(kids) == 1 and not atomic_style(c)
                if (layer or lone) and not atomic_style(c):
                    walk(c, m @ parse_transform(c.get('transform')))
                    continue
            units.append((c, m))

    walk(root, np.eye(3))
    return units


def canvas_scale(root, n):
    vb = root.get('viewBox')
    if vb:
        w = float(re.findall(NUM, vb)[2])
    else:
        w = float(re.findall(NUM, root.get('width') or '128')[0])
    return n / w, w


def render(root, n):
    """root element -> RGBA numpy (n, n, 4) uint8 through rsvg-convert"""
    data = etree.tostring(root)
    p = subprocess.run(['rsvg-convert', '-f', 'png', '-w', str(n), '-h', str(n)], input=data, capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode())
    return np.array(Image.open(io.BytesIO(p.stdout)).convert('RGBA'))


def isolate(root, units, keep):
    """copy of the drawing holding only unit `keep` (and every ancestor path to it)"""
    r2 = copy.deepcopy(root)
    u2 = find_units(r2)
    for i, (e, m) in enumerate(u2):
        if i != keep:
            e.getparent().remove(e)
    return r2


def has_blur(root, unit):
    filters = {}
    for f in root.iter('{%s}filter' % SVG):
        filters[f.get('id')] = f
    els = [unit] + list(unit.iter())
    for e in els:
        if not isinstance(e.tag, str):
            continue
        ref = prop(e, 'filter')
        m = re.match(r'url\(#([^)]+)\)', ref or '')
        if m and m.group(1) in filters:
            for b in filters[m.group(1)].iter('{%s}feGaussianBlur' % SVG):
                sd = [float(x) for x in re.findall(NUM, b.get('stdDeviation') or '0')]
                if sd and max(sd) > 0:
                    return True
    return False


def analyse(root, n):
    """per unit: features from the isolated rendering and the XML"""
    units = find_units(root)
    out = []
    for i, (e, m) in enumerate(units):
        a = render(isolate(root, units, i), n).astype(np.float64)
        alpha = a[..., 3] / 255.0
        tot = alpha.sum()
        covered = alpha > 0.04
        y = (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]) / 255.0
        luma = float((alpha * y).sum() / tot) if tot > 0 else 0.0
        mean_alpha = float(alpha[covered].mean()) if covered.any() else 0.0
        # contrast with the sheet's mid-grey (128), the weight a measurement of the part in the viewer can see
        weight = float((alpha * (np.abs(a[..., 0] - 128) + np.abs(a[..., 1] - 128) + np.abs(a[..., 2] - 128)) / 255.0).sum() / (n * n))
        cols = np.where((a[..., 3] >= 16).any(axis=0))[0]
        x0, x1 = (int(cols[0]), int(cols[-1]) + 1) if len(cols) else (None, None)
        out.append(dict(index=i, id=e.get('id'), tag=ln(e), luma=round(luma, 3), mean_alpha=round(mean_alpha, 3),
                        area=round(float(tot / (n * n)), 4), weight=round(weight, 4), blurred=has_blur(root, e), x0=x0, x1=x1))
    return units, out


def classify_B(feats):
    levels = []
    for f in feats:
        if f['index'] == 0:
            lv, why = 0.0, 'lowest'
        elif f['x0'] is None:
            lv, why = 0.0, 'empty'
        elif f['luma'] <= 0.25 and (f['blurred'] or f['mean_alpha'] < 0.85):
            lv, why = 0.0, 'shadow'
        elif f['luma'] >= 0.75 and f['area'] <= 0.12:
            lv, why = 1.0, 'highlight'
        else:
            lv, why = 0.5, 'body'
        levels.append((lv, why))
    return levels


def load_depthmap(depthdir, icon):
    ctx, name = icon.split('/')
    return json.load(open(f'{depthdir}/{ctx}/{name}.json'))


def levels_C(feats, dm):
    owner = {}
    for o in dm['objects']:
        for pid in o['parts']:
            assert pid not in owner, 'part in two objects: ' + pid
            owner[pid] = (float(o['level']), o['name'])
    out = []; inherited = []
    last = None
    for i, f in enumerate(feats):
        if f['id'] in owner:
            last = owner[f['id']]; out.append(last)
        else:
            out.append(None); inherited.append(f['id'])
    first = next((x for x in out if x), None)
    cur = None
    for i, x in enumerate(out):
        if x: cur = x
        else: out[i] = cur or first
    return out, inherited


def levels_for(rule, feats, dm=None):
    n = len(feats)
    if rule == 'C':
        return levels_C(feats, dm)[0]
    if rule == 'A':
        return [((i / (n - 1)) if n > 1 else 0.0, 'order') for i in range(n)]
    return classify_B(feats)


def effective_budget(levels, feats, n, budget):
    """largest B <= budget with nothing cut by the picture's edge; (B_eff, limiting unit index or None)"""
    best, who = budget, None
    for (lv, _), f in zip(levels, feats):
        if lv <= 0 or f['x0'] is None:
            continue
        room = min(f['x0'], n - f['x1'])          # pixels free on the tighter side
        allowed = 2.0 * room / lv                  # B * lv / 2 <= room
        if allowed < best:
            best, who = allowed, f['index']
    return max(best, 0.0), who


def shifted_view(root, units, parallaxes, eye, n, only=None):
    """render with each unit shifted horizontally: eye +1 (left) sees +p/2, eye -1 (right) sees -p/2.
    only=i keeps unit i alone (for the probes and the checks)"""
    r2 = copy.deepcopy(root)
    u2 = find_units(r2)
    s, w = canvas_scale(r2, n)
    for i, ((e, m), p) in enumerate(zip(u2, parallaxes)):
        if only is not None and i != only:
            e.getparent().remove(e)
            continue
        dx_user = eye * (p / 2.0) / s
        lin = m[:2, :2]
        t = np.linalg.solve(lin, np.array([dx_user, 0.0]))
        g = etree.Element('{%s}g' % SVG)
        g.set('transform', 'translate(%.8g,%.8g)' % (t[0], t[1]))
        parent = e.getparent()
        parent.replace(e, g)
        g.append(e)
    return render(r2, n)


def make(oxy, icon, n, strength_pct, rule, out_png=None, analysis=None, probe=False, depthdir=None):
    path, kind = source_path(oxy, icon, n)
    root = load_svg(path)
    if analysis is None:
        analysis = analyse(root, n)
    units, feats = analysis
    dm = load_depthmap(depthdir, icon) if rule == 'C' else None
    levels = levels_for(rule, feats, dm)
    inherited = levels_C(feats, dm)[1] if rule == 'C' else []
    budget = STRENGTHS[str(strength_pct)] * n
    beff, who = effective_budget(levels, feats, n, budget)
    par = [lv * beff for lv, _ in levels]
    left = shifted_view(root, units, par, +1, n)
    right = shifted_view(root, units, par, -1, n)
    pic = np.concatenate([left, right], axis=1)
    # the probes' parts, chosen so that a shift can be measured on the sheet (grey 128): front = the most popped part among
    # those whose contrast with the grey, summed over the picture, is at least 1 % of the picture (weight >= 0.01); back = the
    # least popped one among those with weight >= 0.004; ties go to the larger weight
    def pick(minw, best):
        c = [i for i, f in enumerate(feats) if f['x0'] is not None and f['weight'] >= minw] \
            or [max((i for i, f in enumerate(feats) if f['x0'] is not None), key=lambda i: feats[i]['weight'])]
        return best(c, key=lambda i: (par[i], (1 if best is max else -1) * feats[i]['weight']))
    front = pick(0.01, max)
    back = pick(0.004, min)
    if out_png:
        os.makedirs(os.path.dirname(out_png), exist_ok=True)
        Image.fromarray(pic, 'RGBA').save(out_png, optimize=True)
        if probe:
            # the front part alone and the back part alone, shifted exactly as in the icon (for measuring)
            for tag, k in (('front', front), ('back', back)):
                pr = np.concatenate([shifted_view(root, units, par, +1, n, only=k), shifted_view(root, units, par, -1, n, only=k)], axis=1)
                Image.fromarray(pr, 'RGBA').save(out_png[:-4] + '.probe-' + tag + '.png', optimize=True)
    meta = dict(icon=icon, size=n, source=os.path.relpath(path, oxy), source_kind=kind, rule=rule,
                strength_percent=strength_pct, budget_px=round(budget, 4), budget_effective_px=round(beff, 4),
                budget_reduced=beff < budget - 1e-9, inherited_parts=inherited, limited_by_unit=who, units=len(units),
                front_unit=front, front_parallax_px=round(par[front], 4),
                back_unit=back, back_parallax_px=round(par[back], 4),
                parts=[dict(f, level=lv, role=why, parallax_px=round(p, 4)) for f, (lv, why), p in zip(feats, levels, par)])
    return pic, meta


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--oxygen-icons', required=True, help='path of the oxygen-icons checkout')
    ap.add_argument('--icons', nargs='+', required=True, help='context/name, e.g. devices/computer')
    ap.add_argument('--sizes', nargs='+', type=int, default=[32, 48, 128, 256])
    ap.add_argument('--out', required=True, help='output folder: <out>/<rule>-<pct>/<N>/<context>/<name>.png')
    ap.add_argument('--rules', nargs='+', default=['A', 'B', 'C'])
    ap.add_argument('--depthmaps', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'depthmaps'))
    ap.add_argument('--probe', action='store_true', help='also write <name>.probe-front.png and .probe-back.png (front / back part alone)')
    ap.add_argument('--strengths', nargs='+', default=['2', '4', '6'])
    a = ap.parse_args()
    allmeta = []
    for icon in a.icons:
        for n in a.sizes:
            path, kind = source_path(a.oxygen_icons, icon, n)
            analysis = analyse(load_svg(path), n)
            for rule in a.rules:
                for pct in a.strengths:
                    ctx, name = icon.split('/')
                    png = f'{a.out}/{rule}-{pct}/{n}/{ctx}/{name}.png'
                    pic, meta = make(a.oxygen_icons, icon, n, pct, rule, png, analysis, a.probe, a.depthmaps)
                    assert pic.shape == (n, 2 * n, 4)
                    allmeta.append(meta)
                    print(icon, n, rule, pct, 'units', meta['units'], 'B', meta['budget_px'], '->', meta['budget_effective_px'],
                          'REDUCED' if meta['budget_reduced'] else '', flush=True)
    json.dump(allmeta, open(a.out + '/meta.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
