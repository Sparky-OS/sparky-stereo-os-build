"""Compare rendered values (qt_render, rsvg_render) with the reference values in cases.json.

Usage: python3 -I compare.py CASES.json RESULTS.jsonl [RESULTS.jsonl ...] --out REPORT_PREFIX
Writes REPORT_PREFIX.txt (one line per case and target) and REPORT_PREFIX.json (counts).

A value passes when its error is within the precision CSS requires for the colour's own space (CSS Color 4 16.2 to
16.5, CSS Color HDR 10.1), or, where the target format holds fewer bits than that, within two of the target's
own quantization steps at that value (the line then says "target-limited").  Gamut mapping (CSS Color 4 14.2) and a
dropped invalid declaration must also be reported in the renderer's messages.
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ref  # noqa: E402

QT_SPACE = {None: 'srgb', 'DisplayP3': 'display-p3', 'Bt2020': 'rec2020', 'SRgbLinear': 'srgb-linear',
            'Bt2100Pq': 'rec2100-pq'}


def step(value, fmt):
    """The target format's quantization step at value."""
    if fmt in ('ARGB32',):
        return 1 / 255
    if fmt == 'RGBA64':
        return 1 / 65535
    v = max(abs(value), 2 ** -14)
    e = math.floor(math.log2(v))
    if fmt == 'RGBA16FPx4':
        return 2.0 ** (e - 10)
    return 2.0 ** (e - 23)


# Limits of the layers beneath the SVG renderers, named so a result short of CSS's precision says which layer stops it
LAYER_LIMITS = {
    ('qt', 'gradient'): ('qtbase QPainter raster gradients: QGradientCache, 1024 entries of QRgba64, [0, 1] only',
                         2.5 / 65535),
    ('rsvg', 'solid'): ('cairo: cairo_set_source_rgba clamps to [0, 1]; pixman solid fills are 16 bits', 2.5 / 65535),
    ('rsvg', 'gradient'): ('cairo: colour stops clamp to [0, 1]; pixman gradient stops are 16 bits', 2.5 / 65535),
}


def bits_of(err):
    return 30.0 if err <= 0 else min(30.0, -math.log2(err))


def colour_message(msgs):
    keys = ('colo', 'gamut', 'css', 'parse error', 'invalid', 'unsupported')
    return [m for m in msgs if any(k in m.lower() for k in keys) and 'base_uri' not in m]


def main():
    args = sys.argv[1:]
    out = args[args.index('--out') + 1]
    files = [a for a in args[1:args.index('--out')]]
    cases = json.load(open(args[0]))
    byid = {c['id']: c for c in cases['cases']}
    results = []
    meta = []
    precision = []
    for f in files:
        for line in open(f):
            line = line.strip()
            if not line:
                continue
            o = json.loads(line)
            if 'precision' in o:
                precision.append(o)
            elif 'id' in o:
                results.append(o)
            else:
                meta.append(o)
    lines = []
    counts = {}
    palette = {}
    for m in meta:
        lines.append('# ' + json.dumps(m))
        if 'palette_text' in m:
            palette = m
    for r in results:
        c = byid[r['id']]
        renderer, fmt, cs = r['target'].split(':')
        msgs = r.get('messages', [])
        cm = colour_message(msgs)
        px = r['pixels'][0]
        key = (renderer, c['form'])
        if c['form'] == 'invalid':
            black = max(abs(px[0]), abs(px[1]), abs(px[2]), abs(px[3] - 1)) < 2 / 255
            ok = black and bool(cm)
            verdict = 'PASS' if ok else 'FAIL'
            detail = 'drawn %s, %s' % ('black (the dropped declaration)' if black else 'not black %s' % px,
                                      'warned: %s' % cm[0][:120] if cm else 'NO WARNING')
        elif c.get('context') == 'system':
            if renderer == 'qt' and palette:
                want = palette['palette_text']
                pal = ref.Color('srgb', [int(want[i:i + 2], 16) / 255 for i in (3, 5, 7)])
                space = QT_SPACE[None if cs == 'none' else cs]
                extended = fmt in ('RGBA16FPx4', 'RGBA32FPx4') and space not in ('rec2100-pq',)
                rgb, _, _ = ref.target_value(pal, space, not extended)
                err = max(abs(a - b) for a, b in zip(px[:3], rgb))
                layer = LAYER_LIMITS.get((renderer, c['form']))
                ok = err <= max(1.5 / 65535, 2 * step(max(rgb), fmt), layer[1] if layer else 0)
                verdict = 'PASS' if ok else 'FAIL'
                detail = 'palette text %s in %s, got %s, error %.2g' % (want, space, [round(v, 4) for v in px[:3]], err)
            else:
                ok = bool(cm)
                verdict = 'PASS' if ok else 'FAIL'
                detail = 'no palette; %s' % ('warned: %s' % cm[0][:120] if cm else 'NO WARNING, drew %s' % [round(v, 4) for v in px])
        else:
            e = c['expected'].get(r['target'])
            if e is None:
                continue
            want = e['rgb'] + [e['alpha']]
            # gradients: every sampled point holds the same colour (both stops are the colour)
            errs = []
            channels = range(4) if e['alpha'] > 0 else (3,)
            for p in r['pixels']:
                errs.append(max(abs(p[i] - want[i]) for i in channels))
            err = max(errs)
            req = c['required_bits']
            allowed_css = 2.0 ** -req
            tstep = max(step(v, fmt) for v in want)
            target_bits = bits_of(tstep)
            limited = target_bits < req
            allowed = max(allowed_css, 2 * tstep) if limited else max(allowed_css, 1.01 * tstep)
            if 0 < e['alpha'] < 1:
                allowed /= e['alpha']
            ok = err <= allowed
            mapped_ok = (not e['gamut_mapped']) or bool(cm)
            verdict = 'PASS' if ok and mapped_ok else 'FAIL'
            layer_note = ''
            layer = LAYER_LIMITS.get((renderer, c['form']))
            if verdict == 'FAIL' and layer:
                # short of CSS's precision: is it the layer beneath, and did the renderer say so where it changed a value?
                b = e.get('bounded', {'rgb': e['rgb'], 'gamut_mapped': e['gamut_mapped']})
                bwant = b['rgb'] + [e['alpha']]
                berr = max(max(abs(p[i] - bwant[i]) for i in channels) for p in r['pixels'])
                changed = b['gamut_mapped'] or e['gamut_mapped']
                if berr <= max(layer[1], allowed) and (not changed or cm):
                    verdict = 'LIMIT'
                    layer_note = '; limited by %s (%.1f bits against the [0, 1] value%s)' % (
                        layer[0], bits_of(berr), ', warned' if changed else '')
            detail = 'error %.3g (%.1f bits; %s needs %d%s), got %s want %s%s%s' % (
                err, bits_of(err), c['precision_clause'], req, ', target-limited to %.0f' % target_bits if limited else '',
                [round(v, 6) for v in r['pixels'][0]], [round(v, 6) for v in want],
                '' if not e['gamut_mapped'] else (' gamut-mapped, warned' if cm else ' gamut-mapped, NO WARNING'),
                layer_note)
        counts.setdefault(r['target'], {'PASS': 0, 'LIMIT': 0, 'FAIL': 0})[verdict] += 1
        lines.append('%s %-34s %-24s %s' % (verdict, c['id'], r['target'], detail))
        if msgs and verdict == 'FAIL' and not cm:
            lines.append('     messages: %s' % '; '.join(msgs)[:300])
    lines.append('')
    lines.append('# precision fixtures: distinct green values along one row')
    for p in precision:
        fx = next(x for x in cases['precision'] if x['id'] == p['precision'])
        lv = fx['levels']
        n = p['distinct']
        reached = [b for b in ('8', '10', '12', '16') if n >= lv[b] * 0.9]
        if n <= 1:
            verdict = 'one value: the fixture is not drawn at any depth'
        elif not reached:
            verdict = 'below 8 bits'
        else:
            top = reached[-1]
            nxt = {'8': '10', '10': '12', '12': '16'}.get(top)
            verdict = '%s bits' % top if (nxt is None or lv[nxt] != lv[top]) else 'at most %s bits' % nxt
        lines.append('%-12s %-24s %5d distinct (8 bits: %s, 10: %s, 12: %s, 16: %s) -> %s' % (
            p['precision'], p['target'], n, lv['8'], lv['10'], lv['12'], lv['16'], verdict))
    open(out + '.txt', 'w').write('\n'.join(lines) + '\n')
    summary = {'counts': counts, 'precision': [{'fixture': p['precision'], 'target': p['target'],
                                                'distinct': p['distinct']} for p in precision]}
    json.dump(summary, open(out + '.json', 'w'), indent=1)
    for t, c in sorted(counts.items()):
        print('%-28s %4d PASS %4d LIMIT %4d FAIL' % (t, c['PASS'], c['LIMIT'], c['FAIL']))


if __name__ == '__main__':
    main()
