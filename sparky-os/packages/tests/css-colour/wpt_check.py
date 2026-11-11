"""Check a colour engine against the web-platform-tests vectors (wpt_vectors.py).

Usage: python3 -I wpt_check.py VECTORS.json [--engine ref|json:RESULTS.json] [--fails N]
The reference engine (ref.py) is checked directly.  Another engine supplies a JSON object mapping each
specified string to {"ok": bool, "space": str, "c": [c0, c1, c2] (null for none), "alpha": a|null}.
Comparison follows WPT's color-testcommon.js: numbers within 0.01 in the expected value's own units, the same
missing components; rgb() and rgba() expectations are 8-bit serializations, compared within 0.5 of 255.
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ref  # noqa: E402

SYSTEM = {k: ref.rgb8(v) for k, v in {
    'canvas': 0xffffff, 'canvastext': 0x000000, 'linktext': 0x0000ee, 'visitedtext': 0x551a8b,
    'activetext': 0xff0000, 'buttonface': 0xefefef, 'buttontext': 0x000000, 'buttonborder': 0x767676,
    'field': 0xffffff, 'fieldtext': 0x000000, 'highlight': 0x3584e4, 'highlighttext': 0xffffff,
    'selecteditem': 0x3584e4, 'selecteditemtext': 0xffffff, 'mark': 0xffff00, 'marktext': 0x000000,
    'graytext': 0x808080, 'accentcolor': 0x3584e4, 'accentcolortext': 0xffffff}.items()}


def ctx():
    # WPT's computed tests run with color: black unless they set it; the system colours above are a light scheme
    return ref.Context(current=ref.rgb8(0x000000), system=SYSTEM)


def expected_color(s):
    c = ctx()
    c.noclamp = True
    return ref.parse(s, c)


def close(a, b, eps, hue=False):
    if a is None or b is None:
        return a is None and b is None
    if hue:
        d = abs((a - b + 180) % 360 - 180)
        return d <= eps
    if math.isinf(b) or math.isinf(a):
        return a == b
    return abs(a - b) <= eps


def compare(got, exp_s, epsilon=None):
    exp = expected_color(exp_s)
    legacy_rgb = exp_s.strip().lower().startswith(('rgb(', 'rgba('))
    space = exp.space
    if got.space != space:
        g = got.to(space)
    else:
        g = got
    eps = epsilon or 0.01
    scale = 1.0
    if legacy_rgb:
        scale, eps = 255.0, 0.5
    hi = ref.POLAR.get(space)
    for i in range(3):
        a = None if g.c[i] is None else g.c[i] * scale
        b = None if exp.c[i] is None else exp.c[i] * scale
        if legacy_rgb:
            a = 0.0 if a is None else a
            b = 0.0 if b is None else b
        if hi == i and (a is None) != (b is None):
            # a hue that one side calls powerless is only a difference if chroma is not zero
            return False, 'hue missing differs: %r vs %r' % (g, exp)
        if not close(a, b, eps, hue=(hi == i)):
            return False, 'component %d: %r vs %r' % (i, g, exp)
    ga, ea = g.alpha, exp.alpha
    if legacy_rgb:
        ga = 0.0 if ga is None else ga
        ea = 0.0 if ea is None else ea
    if not close(ga, ea, 0.01):
        return False, 'alpha: %r vs %r' % (g, exp)
    return True, ''


def run_ref(vectors):
    results = {}
    for v in vectors:
        try:
            results[v['specified']] = ('ok', ref.parse(v['specified'], ctx()))
        except ref.Invalid as e:
            results[v['specified']] = ('invalid', str(e))
        except (ValueError, ZeroDivisionError, OverflowError) as e:
            results[v['specified']] = ('error', repr(e))
    return results


def run_json(path):
    data = json.load(open(path))
    results = {}
    for s, r in data.items():
        if r.get('ok'):
            results[s] = ('ok', ref.Color(r['space'], r['c'], r['alpha']))
        else:
            results[s] = ('invalid', r.get('error', ''))
    return results


def main():
    vec = json.load(open(sys.argv[1]))['vectors']
    engine = 'ref'
    nfail = 20
    args = sys.argv[2:]
    if '--engine' in args:
        engine = args[args.index('--engine') + 1]
    if '--fails' in args:
        nfail = int(args[args.index('--fails') + 1])
    results = run_ref(vec) if engine == 'ref' else run_json(engine.split(':', 1)[1])
    tally = {}
    fails = []
    for v in vec:
        kind = v['kind']
        r = results.get(v['specified'], ('missing', ''))
        if kind == 'invalid':
            ok = r[0] == 'invalid'
            why = '' if ok else 'accepted %r' % (r[1],)
        elif kind == 'valid':
            ok = r[0] == 'ok'
            why = '' if ok else r[1]
        else:
            if r[0] != 'ok':
                ok, why = False, r[1]
            elif v['expected'] is None or v['specified'].strip().lower() == 'currentcolor':
                ok, why = True, ''
            else:
                try:
                    ok, why = compare(r[1], v['expected'], v.get('epsilon'))
                except ref.Invalid as e:
                    ok, why = False, 'expected value did not parse: %s' % e
        t = tally.setdefault((v['file'], kind), [0, 0])
        t[0 if ok else 1] += 1
        if not ok:
            fails.append((v, why))
    total_ok = sum(t[0] for t in tally.values())
    total = sum(t[0] + t[1] for t in tally.values())
    for (f, k), (p, q) in sorted(tally.items()):
        print('%-50s %-8s %5d pass %4d fail' % (f, k, p, q))
    print('TOTAL %d of %d pass' % (total_ok, total))
    for v, why in fails[:nfail]:
        print('FAIL', v['kind'], repr(v['specified']), '->', repr(v['expected']), ':', why)


if __name__ == '__main__':
    main()
