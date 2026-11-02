"""The specifications' own worked examples, checked against the reference engine (ref.py).

Each row: (clause, specified colour, expected colour or values, tolerance).  Run: python3 -I spec_examples.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ref  # noqa: E402

WHITE = ref.rgb8(0xffffff)
LIME = ref.rgb8(0x00ff00)

ROWS = [
    # CSS Color HDR 1, WD 26 October 2026
    ('HDR 8.1: media white is rec2100-pq 0.5807 (four figures)', 'color(rec2100-pq 0.5807 0.5807 0.5807)', WHITE, 2e-4),
    ('HDR 8.2: media white is rec2100-hlg 0.75', 'color(rec2100-hlg 0.75 0.75 0.75)', WHITE, 2e-4),
    ('HDR 8.3: rec2100-linear 1 1 1 is HDR reference white', 'color(rec2100-linear 1 1 1)', WHITE, 1e-9),
    ('HDR 6.3: diffuse white is ictcp(0.58069 0 0)', 'ictcp(0.58069 0 0)', WHITE, 2e-4),
    # HDR 6.3 to 6.5 call ictcp(0.5393 -0.2643 -0.0625), jzazbz(0.17542 -0.1179 0.1092) and jzczhz(0.17542 0.1614 132.50)
    # sRGB lime; the specification's own section 11 sample code gives lime as the three values below (ERRATA rows).
    ('HDR 6.4: diffuse white is jzazbz(0.22207 -0.00016 -0.00012)', 'jzazbz(0.22207 -0.00016 -0.00012)', WHITE, 2e-4),
    ('HDR 11.5 sample code: lime is ictcp(0.53976 -0.28125 -0.04948)', 'ictcp(0.53976 -0.28125 -0.04948)', LIME, 1e-3),
    ('HDR 11.4 sample code: lime is jzazbz(0.17681 -0.10904 0.11899)', 'jzazbz(0.17681 -0.10904 0.11899)', LIME, 1e-3),
    ('HDR 6.5: lime is jzczhz(Jz 0.17681 per 11.4) 0.1614 132.50', 'jzczhz(0.17681 0.1614 132.5025)', LIME, 1e-3),
    # CSS Color 4, CRD 1 November 2026
    ('C4 14.1.3: display-p3 yellow is srgb 1 1 -0.3463', 'color(display-p3 1 1 0)', ref.Color('srgb', [1, 1, -0.3463]), 2e-4),
    ('C4 14.1.3: display-p3 yellow is oklch(0.96476 0.24503 110.23)', 'color(display-p3 1 1 0)', ref.Color('oklch', [0.96476, 0.24503, 110.23]), 2e-4),
    ('C4 10.1: rec2020 lime is display-p3 -0.350289 1.00707 -0.144209', 'color(rec2020 0.42053 0.979780 0.00579)', ref.Color('display-p3', [-0.350289, 1.00707, -0.144209]), 2e-4),
    ('C4 14.1.1: rec2020 0.54 0.9 0 is oklch(80.72% 0.3296 141.6)', 'color(rec2020 0.54 0.9 0)', ref.Color('oklch', [0.8072, 0.3296, 141.6]), 1e-3),
    ('C4 14.1.1: prophoto 0.2 1 0.1 is display-p3 -0.5782 1.067 -0.2363', 'color(prophoto-rgb 0.2 1.0 0.1)', ref.Color('display-p3', [-0.5782, 1.067, -0.2363]), 1e-3),
    ('C5 6: device-cmyk(0 81% 81% 30%) is rgb(178 34 34)', 'device-cmyk(0 81% 81% 30%)', ref.Color('srgb', [178 / 255, 34 / 255, 34 / 255]), 3e-3),
    ('C5 3.2: color-mix(in lch, purple 30%, plum 30%) has alpha 0.6', 'color-mix(in lch, purple 30%, plum 30%)', ref.Color('lch', [51.51, 52.21, 325.8], 0.6), 0.02),
    ('C5 3.3: color-mix(in lch, peru 40%, palegoldenrod)', 'color-mix(in lch, peru 40%, palegoldenrod)', ref.Color('lch', [79.7256, 40.448, 84.771]), 0.01),
]


def gamut_rows():
    # CSS Color 4 section 14.1.3: display-p3 yellow gamut-mapped into sRGB is about srgb(0.99116 0.99733 0.00001)
    rgb, mapped = ref.gamut_map(ref.parse('color(display-p3 1 1 0)'), 'srgb')
    ok = mapped and all(abs(a - b) <= 0.01 for a, b in zip(rgb, [0.99116, 0.99733, 0.00001]))
    yield ok, 'C4 14.1.3: display-p3 yellow mapped to sRGB %s, example 0.99116 0.99733 0.00001' % [round(v, 5) for v in rgb]
    # CSS Color 4 section 14.2: color(display-p3 1.1 0.4 0.2) maps to "such as" display-p3 1 0.473 0.314
    rgb, mapped = ref.gamut_map(ref.parse('color(display-p3 1.1 0.4 0.2)'), 'display-p3')
    ok = mapped and all(abs(a - b) <= 0.03 for a, b in zip(rgb, [1, 0.473, 0.314]))
    yield ok, 'C4 14.2: display-p3 1.1 0.4 0.2 mapped to %s, example "such as" 1 0.473 0.314' % [round(v, 4) for v in rgb]
    rgb, mapped = ref.gamut_map(ref.parse('oklch(76% 0.27 60)'), 'display-p3')
    ok = mapped and all(abs(a - b) <= 0.03 for a, b in zip(rgb, [1, 0.546, 0]))
    yield ok, 'C4 14.2: oklch(76%% 0.27 60) mapped to display-p3 %s, example "such as" 1 0.546 0' % [round(v, 4) for v in rgb]
    # CSS Color HDR section 5: hdr-color example at headroom 1 is absolute X=243.664, Y=275.713, Z=244.000
    c = ref.parse('color-hdr(color(rec2100-linear 0.9 1.0 0.8) 0, color(rec2100-linear 1.8 2.0 1.5) 2)',
                  ref.Context(headroom=1.0))
    xyz = [v * ref.YW for v in c.xyz()]
    ok = all(abs(a - b) <= 0.01 for a, b in zip(xyz, [243.664, 275.713, 244.000]))
    yield ok, 'HDR 5: hdr-color at headroom 1 gives absolute XYZ %s, example 243.664 275.713 244.000' % [round(v, 3) for v in xyz]
    for H, want in ((0, 'color(rec2100-linear 0.9 1.0 0.8)'), (2, 'color(rec2100-linear 1.8 2.0 1.5)')):
        c = ref.parse('color-hdr(color(rec2100-linear 0.9 1.0 0.8) 0, color(rec2100-linear 1.8 2.0 1.5) 2)',
                      ref.Context(headroom=H))
        w = ref.parse(want).xyz()
        ok = all(abs(a - b) <= 1e-4 for a, b in zip(c.xyz(), w))
        yield ok, 'HDR 5: hdr-color at headroom %d is %s' % (H, want)


def main():
    fails = 0
    for clause, spec, want, tol in ROWS:
        got = ref.parse(spec)
        g = got.to(want.space)
        diffs = []
        for i in range(3):
            a = 0.0 if g.c[i] is None else g.c[i]
            b = want.c[i]
            d = abs(a - b)
            if ref.POLAR.get(want.space) == i:
                d = abs((a - b + 180) % 360 - 180) / 360
            diffs.append(d)
        da = abs((1.0 if got.alpha is None else got.alpha) - want.alpha)
        ok = max(diffs) <= tol and da <= 1e-6
        fails += not ok
        print('%s %s -> %s %s' % ('PASS' if ok else 'FAIL', clause, want.space, [round(0.0 if v is None else v, 6) for v in g.c]))
    for ok, line in gamut_rows():
        fails += not ok
        print('%s %s' % ('PASS' if ok else 'FAIL', line))
    print('%d failing' % fails)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
