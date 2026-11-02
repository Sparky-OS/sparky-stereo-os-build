"""ORDER 348 test set: one SVG per colour syntax and space of CSS Color 4, CSS Color 5 and CSS Color HDR, each also as
a gradient, plus ramps and step wedges that tell 8, 10, 12 and 16 bits apart.  Expected values come from the
reference engine (tools/csscolor/ref.py, the specifications' own sample code).

Usage: python3 -I make_corpus.py OUTDIR
Writes OUTDIR/svg/*.svg and OUTDIR/cases.json.
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ref  # noqa: E402

# (id, colour, the clause that defines its syntax, the precision clause and its minimum bits)
P8 = ('C4 16.2', 8)
P16LAB = ('C4 16.3', 16)
P16OK = ('C4 16.4', 16)


def p16_5(space):
    bits = {'srgb': 10, 'srgb-linear': 12, 'display-p3': 10, 'display-p3-linear': 12, 'a98-rgb': 10,
            'prophoto-rgb': 12, 'rec2020': 12, 'xyz': 16, 'xyz-d50': 16, 'xyz-d65': 16}
    if space in bits:
        return ('C4 16.5', bits[space])
    return ('HDR 10.1', {'rec2100-pq': 10, 'rec2100-hlg': 10, 'rec2100-linear': 16}[space])


CASES = [
    ('hex3', '#3a7', 'C4 5.2', P8),
    ('hex4', '#3a7c', 'C4 5.2', P8),
    ('hex6', '#336699', 'C4 5.2', P8),
    ('hex8', '#336699cc', 'C4 5.2', P8),
    ('named', 'rebeccapurple', 'C4 6.1', P8),
    ('transparent', 'transparent', 'C4 6.3', P8),
    ('currentcolor', 'currentcolor', 'C4 6.4', P8),
    ('system-canvastext', 'CanvasText', 'C4 6.2', P8),
    ('system-deprecated', 'WindowText', 'C4 Appendix A', P8),
    ('rgb-legacy', 'rgb(51, 102, 153)', 'C4 5.1', P8),
    ('rgb-legacy-pct', 'rgb(20%, 40%, 60%)', 'C4 5.1', P8),
    ('rgba-legacy', 'rgba(51, 102, 153, 0.8)', 'C4 5.1', P8),
    ('rgb-modern-fraction', 'rgb(31.4159 159.2653 89.7932)', 'C4 5.1', P8),
    ('rgb-modern-alpha', 'rgb(31.4159 159.2653 89.7932 / 80%)', 'C4 5.1', P8),
    ('rgb-none', 'rgb(none 159.2653 89.7932)', 'C4 4.4', P8),
    ('hsl-legacy', 'hsl(210, 50%, 40%)', 'C4 7', P8),
    ('hsla-legacy', 'hsla(210, 50%, 40%, 0.75)', 'C4 7', P8),
    ('hsl-modern', 'hsl(210.123 50.5% 40.25%)', 'C4 7', P8),
    ('hwb', 'hwb(150.5 20.25% 10.125%)', 'C4 8', P8),
    ('lab', 'lab(52.2345% 40.1645 59.9971)', 'C4 9.3', P16LAB),
    ('lab-wide', 'lab(70.5% 85.25 -60.75)', 'C4 9.3', P16LAB),
    ('lch', 'lch(52.2345% 72.2 56.2)', 'C4 9.3', P16LAB),
    ('oklab', 'oklab(59.686% 0.1009 0.1192)', 'C4 9.4', P16OK),
    ('oklch', 'oklch(0.6 0.2 30)', 'C4 9.4', P16OK),
    ('oklch-wide', 'oklch(0.7 0.3 145)', 'C4 9.4', P16OK),
    ('srgb', 'color(srgb 0.123457 0.654321 0.876543)', 'C4 10.2', p16_5('srgb')),
    ('srgb-linear', 'color(srgb-linear 0.0123457 0.3654321 0.6876543)', 'C4 10.3', p16_5('srgb-linear')),
    ('display-p3', 'color(display-p3 0.423457 0.554321 0.676543)', 'C4 10.4', p16_5('display-p3')),
    ('display-p3-wide', 'color(display-p3 1 0.25 0)', 'C4 10.4', p16_5('display-p3')),
    ('display-p3-linear', 'color(display-p3-linear 0.123457 0.354321 0.476543)', 'C4 10.5', p16_5('display-p3-linear')),
    ('a98-rgb', 'color(a98-rgb 0.423457 0.554321 0.676543)', 'C4 10.6', p16_5('a98-rgb')),
    ('prophoto-rgb', 'color(prophoto-rgb 0.423457 0.454321 0.576543)', 'C4 10.7', p16_5('prophoto-rgb')),
    ('rec2020', 'color(rec2020 0.423457 0.554321 0.676543)', 'C4 10.8', p16_5('rec2020')),
    ('rec2020-wide', 'color(rec2020 0.42053 0.979780 0.00579)', 'C4 10.8', p16_5('rec2020')),
    ('xyz', 'color(xyz 0.2123457 0.2654321 0.3876543)', 'C4 10.9', p16_5('xyz')),
    ('xyz-d50', 'color(xyz-d50 0.2123457 0.2654321 0.2876543)', 'C4 10.9', p16_5('xyz-d50')),
    ('xyz-d65', 'color(xyz-d65 0.2123457 0.2654321 0.3876543)', 'C4 10.9', p16_5('xyz-d65')),
    ('color-pct', 'color(display-p3 42.3457% 55.4321% 67.6543%)', 'C4 10.1', p16_5('display-p3')),
    ('rec2100-pq', 'color(rec2100-pq 0.5 0.45 0.4)', 'HDR 8.1', p16_5('rec2100-pq')),
    ('rec2100-pq-hdr', 'color(rec2100-pq 0.7 0.65 0.6)', 'HDR 8.1', p16_5('rec2100-pq')),
    ('rec2100-hlg', 'color(rec2100-hlg 0.6 0.55 0.5)', 'HDR 8.2', p16_5('rec2100-hlg')),
    ('rec2100-linear', 'color(rec2100-linear 0.2123457 0.3654321 0.4876543)', 'HDR 8.3', p16_5('rec2100-linear')),
    ('rec2100-linear-hdr', 'color(rec2100-linear 2.5 2.25 2)', 'HDR 8.3', p16_5('rec2100-linear')),
    ('ictcp', 'ictcp(0.45 -0.05 0.03)', 'HDR 6.3', ('HDR 10.1', 16)),
    ('jzazbz', 'jzazbz(0.12 0.02 -0.03)', 'HDR 6.4', ('HDR 10.1', 16)),
    ('jzczhz', 'jzczhz(0.12 0.04 300)', 'HDR 6.5', ('HDR 10.1', 16)),
    ('color-mix', 'color-mix(in oklab, #336699 30%, color(display-p3 0.9 0.6 0.1))', 'C5 3', P16OK),
    ('color-mix-default', 'color-mix(teal, gold)', 'C5 3.1', P16OK),
    ('color-mix-hue', 'color-mix(in oklch longer hue, oklch(0.6 0.15 20), oklch(0.7 0.12 200))', 'C4 13.5', P16OK),
    ('color-mix-three', 'color-mix(in srgb-linear, red, lime 25%, blue 25%)', 'C5 3.3', p16_5('srgb-linear')),
    ('relative-rgb', 'rgb(from rebeccapurple calc(r * 1.25) g b)', 'C5 4.3', p16_5('srgb')),
    ('relative-oklch', 'oklch(from #336699 calc(l + 0.1) calc(c * 1.5) calc(h + 30))', 'C5 4.9', P16OK),
    ('relative-color', 'color(from color(display-p3 0.4 0.5 0.6) display-p3 calc(r * 0.9) g calc(b + 0.05))', 'C5 5.1', p16_5('display-p3')),
    ('alpha-function', 'alpha(from color(display-p3 0.4 0.5 0.6) / 0.5)', 'C5 4.10', p16_5('display-p3')),
    ('light-dark', 'light-dark(color(display-p3 0.2 0.4 0.6), color(display-p3 0.8 0.6 0.4))', 'C5 7', p16_5('display-p3')),
    ('contrast-color', 'contrast-color(color(display-p3 0.2 0.3 0.4))', 'C5 8', P8),
    ('device-cmyk', 'device-cmyk(0.1 0.2 0.3 0.05)', 'C5 6', P8),
    ('device-cmyk-modern', 'device-cmyk(10% 20% 30% 5% / 80%)', 'C5 6', P8),
    ('hdr-color', 'color-hdr(color(rec2100-linear 0.9 1.0 0.8) 0, color(rec2100-linear 1.8 2.0 1.5) 2)', 'HDR 5', p16_5('rec2100-linear')),
]
INVALID = [
    ('invalid-space', 'color(profoto-rgb 0.4835 0.9167 0.2188)', 'C4 10.1'),
    ('invalid-syntax', 'lab(50% 40 abc)', 'C4 4.5'),
]

# Qt SVG targets: QImage format, colour space (None: no colour space, read as sRGB), extended range
QT_TARGETS = [
    ('RGBA64', None, False), ('RGBA16FPx4', None, True), ('RGBA32FPx4', None, True),
    ('RGBA64', 'DisplayP3', False), ('RGBA64', 'Bt2020', False),
    ('RGBA32FPx4', 'SRgbLinear', True), ('RGBA32FPx4', 'Bt2100Pq', False), ('RGBA32FPx4', 'Bt2020', True),
    ('ARGB32', None, False),
]
QT_SPACE = {None: 'srgb', 'DisplayP3': 'display-p3', 'Bt2020': 'rec2020', 'SRgbLinear': 'srgb-linear',
            'Bt2100Pq': 'rec2100-pq'}
# librsvg on cairo: image surface formats; cairo clamps colours to [0, 1] and has no colour spaces (sRGB)
RSVG_TARGETS = [('RGBA128F', None, False), ('ARGB32', None, False)]
TARGET_BITS = {'RGBA64': 16, 'RGBA16FPx4': 11, 'RGBA32FPx4': 23, 'ARGB32': 8, 'RGBA128F': 23}

W = 64
H = 16


def svg_solid(colour, how):
    head = '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"' % (W, H)
    tail = '</svg>\n'
    if colour == 'currentcolor':
        return head + ' color="#2a5f8e">' + '<rect width="%d" height="%d" fill="currentcolor"/>' % (W, H) + tail
    if how == 'attr':
        return head + '><rect width="%d" height="%d" fill="%s"/>' % (W, H, colour) + tail
    if how == 'style':
        return head + '><rect width="%d" height="%d" style="fill: %s"/>' % (W, H, colour) + tail
    return head + '><style>rect { fill: %s }</style><rect width="%d" height="%d"/>' % (colour, W, H) + tail


def svg_gradient(colour):
    stop = 'stop-color="%s"' % colour
    extra = ''
    if colour == 'currentcolor':
        extra = ' color="#2a5f8e"'
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"%s><defs>'
            '<linearGradient id="g" x1="0" x2="1" y1="0" y2="0">'
            '<stop offset="0" %s/><stop offset="1" %s/></linearGradient></defs>'
            '<rect width="%d" height="%d" fill="url(#g)"/></svg>\n') % (W, H, extra, stop, stop, W, H)


def context():
    # The reference context: currentcolor from the color attribute; system colours from the renderer's palette,
    # which the measurement reads back (Qt: QGuiApplication::palette(); librsvg has none)
    return ref.Context(current=ref.rgb8(0x2a5f8e))


def expected(colour, space, bounded, ctx):
    # CSS Color HDR section 5: hdr-color() takes the target's headroom; an SDR (bounded) target has none, and an
    # extended-range target takes the HDR colour, which the compositor maps per screen (Daniel's call, ORDER 348)
    ctx.headroom = 0.0 if bounded else 1000.0
    c = ref.parse(colour, ctx)
    rgb, alpha, mapped = ref.target_value(c, space, bounded)
    return rgb, alpha, mapped


def main():
    out = sys.argv[1]
    os.makedirs(os.path.join(out, 'svg'), exist_ok=True)
    cases = []
    ctx = context()
    for cid, colour, clause, (pclause, bits) in CASES:
        forms = [('solid', 'attr'), ('gradient', None)]
        if cid in ('srgb', 'display-p3', 'oklch', 'rec2100-pq', 'color-mix', 'relative-oklch', 'hex8', 'lab'):
            forms += [('solid', 'style'), ('solid', 'sheet')]
        for form, how in forms:
            name = '%s-%s%s' % (cid, form, '' if how in (None, 'attr') else '-' + how)
            text = svg_gradient(colour) if form == 'gradient' else svg_solid(colour, how)
            open(os.path.join(out, 'svg', name + '.svg'), 'w').write(text)
            entry = {'id': name, 'case': cid, 'colour': colour, 'form': form, 'how': how or 'attr',
                     'syntax_clause': clause, 'precision_clause': pclause, 'required_bits': bits,
                     'points': [[8, 8], [W // 2, 8], [W - 8, 8]], 'expected': {}}
            if cid.startswith('system'):
                entry['context'] = 'system'
            for renderer, targets in (('qt', QT_TARGETS), ('rsvg', RSVG_TARGETS)):
                for fmt, cs, extended in targets:
                    space = QT_SPACE[cs] if renderer == 'qt' else 'srgb'
                    key = '%s:%s:%s' % (renderer, fmt, cs or 'none')
                    if cid.startswith('system'):
                        entry['expected'][key] = None
                        continue
                    rgb, alpha, mapped = expected(colour, space, not extended, ctx)
                    entry['expected'][key] = {'rgb': rgb, 'alpha': alpha, 'gamut_mapped': mapped,
                                              'space': space, 'target_bits': TARGET_BITS[fmt]}
                    if extended:
                        # what a layer that holds [0, 1] only must draw: gamut mapped into the target's space
                        brgb, _, bmapped = expected(colour, space, True, ctx)
                        entry['expected'][key]['bounded'] = {'rgb': brgb, 'gamut_mapped': bmapped}
            cases.append(entry)
    for cid, colour, clause in INVALID:
        name = '%s-solid' % cid
        open(os.path.join(out, 'svg', name + '.svg'), 'w').write(svg_solid(colour, 'attr'))
        cases.append({'id': name, 'case': cid, 'colour': colour, 'form': 'invalid', 'how': 'attr',
                      'syntax_clause': clause, 'points': [[8, 8]],
                      'note': 'invalid: the declaration is dropped (CSS Syntax 3, CSS Color 4 4.5), so fill takes its '
                              'initial value, black (SVG 2 13.2); the renderer must also warn'})
    # ramps and wedges that tell 8, 10, 12 and 16 bits apart
    precision = []
    # a narrow ramp: 1/256 of the range over 1024 px
    lo, hi = 0.5, 0.5 + 1 / 256
    text = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="4"><defs><linearGradient id="g" '
            'gradientUnits="userSpaceOnUse" x1="0" x2="1024" y1="0" y2="0"><stop offset="0" stop-color="color(srgb %r %r %r)"/>'
            '<stop offset="1" stop-color="color(srgb %r %r %r)"/></linearGradient></defs>'
            '<rect width="1024" height="4" fill="url(#g)"/></svg>\n') % (lo, lo, lo, hi, hi, hi)
    open(os.path.join(out, 'svg', 'ramp-narrow.svg'), 'w').write(text)
    precision.append({'id': 'ramp-narrow', 'width': 1024, 'height': 4, 'lo': lo, 'hi': hi,
                      'levels': {'8': 2, '10': 5, '12': 17, '16': 257},
                      'note': 'distinct green values across the ramp: a band of 1/256 holds 1 step at 8 bits, '
                              '4 at 10, 16 at 12 and 256 at 16 (plus the end)'})
    # a full ramp over 4096 px: QPainter's gradient table has 1024 entries
    text = ('<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="4"><defs><linearGradient id="g" '
            'gradientUnits="userSpaceOnUse" x1="0" x2="4096" y1="0" y2="0"><stop offset="0" stop-color="color(srgb 0 0 0)"/>'
            '<stop offset="1" stop-color="color(srgb 1 1 1)"/></linearGradient></defs>'
            '<rect width="4096" height="4" fill="url(#g)"/></svg>\n')
    open(os.path.join(out, 'svg', 'ramp-full.svg'), 'w').write(text)
    precision.append({'id': 'ramp-full', 'width': 4096, 'height': 4, 'lo': 0, 'hi': 1,
                      'levels': {'8': 256, '10': 1024, '12': 4096, '16': 4096}})
    # a step wedge of 256 solid rectangles, 4 px each, one 16-bit step apart: (32768 + k) / 65535
    rects = ''.join('<rect x="%d" width="4" height="4" fill="color(srgb %.10f %.10f %.10f)"/>'
                    % ((4 * k,) + ((32768 + k) / 65535,) * 3) for k in range(256))
    open(os.path.join(out, 'svg', 'wedge-16.svg'), 'w').write(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="4">%s</svg>\n' % rects)
    precision.append({'id': 'wedge-16', 'width': 1024, 'height': 4, 'lo': 32768 / 65535, 'hi': 33023 / 65535,
                      'levels': {'8': 1, '10': 1, '12': 16, '16': 256},
                      'note': '256 solid fills one 16-bit step apart: 256 distinct values at 16 bits, 16 at 12, 1 at 8 or 10'})
    json.dump({'cases': cases, 'precision': precision, 'width': W, 'height': H,
               'qt_targets': QT_TARGETS, 'rsvg_targets': RSVG_TARGETS}, open(os.path.join(out, 'cases.json'), 'w'), indent=1)
    print(len(cases), 'cases,', len(precision), 'precision fixtures in', out)


if __name__ == '__main__':
    main()
