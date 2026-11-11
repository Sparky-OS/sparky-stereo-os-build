"""Writes the expected values of Qt SVG's tst_qsvgcsscolor from the reference engine (ref.py), so that the test's
numbers come from the specifications' sample code and not from the code under test.
Usage: python3 -I gen_qt_test_rows.py > rows.inc
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ref  # noqa: E402

# (row name, colour, clause): one per syntax and space of CSS Color 4, CSS Color 5 and CSS Color HDR 1
PARSE = [
    ('hex6', '#336699', 'C4 5.2'), ('hex8', '#33669980', 'C4 5.2'), ('named', 'rebeccapurple', 'C4 6.1'),
    ('transparent', 'transparent', 'C4 6.3'), ('rgb-legacy', 'rgb(51, 102, 153)', 'C4 5.1'),
    ('rgb-modern', 'rgb(31.4159 159.2653 89.7932 / 80%)', 'C4 5.1'), ('hsl', 'hsl(210.123 50.5% 40.25%)', 'C4 7'),
    ('hwb', 'hwb(150.5 20.25% 10.125%)', 'C4 8'), ('lab', 'lab(52.2345% 40.1645 59.9971)', 'C4 9.3'),
    ('lch', 'lch(52.2345% 72.2 56.2)', 'C4 9.3'), ('oklab', 'oklab(59.686% 0.1009 0.1192)', 'C4 9.4'),
    ('oklch', 'oklch(0.6 0.2 30)', 'C4 9.4'), ('srgb', 'color(srgb 0.123457 0.654321 0.876543)', 'C4 10.2'),
    ('srgb-linear', 'color(srgb-linear 0.0123457 0.3654321 0.6876543)', 'C4 10.3'),
    ('display-p3', 'color(display-p3 0.423457 0.554321 0.676543)', 'C4 10.4'),
    ('display-p3-linear', 'color(display-p3-linear 0.123457 0.354321 0.476543)', 'C4 10.5'),
    ('a98-rgb', 'color(a98-rgb 0.423457 0.554321 0.676543)', 'C4 10.6'),
    ('prophoto-rgb', 'color(prophoto-rgb 0.423457 0.454321 0.576543)', 'C4 10.7'),
    ('rec2020', 'color(rec2020 0.423457 0.554321 0.676543)', 'C4 10.8'),
    ('xyz', 'color(xyz 0.2123457 0.2654321 0.3876543)', 'C4 10.9'),
    ('xyz-d50', 'color(xyz-d50 0.2123457 0.2654321 0.2876543)', 'C4 10.9'),
    ('rec2100-pq', 'color(rec2100-pq 0.5 0.45 0.4)', 'HDR 8.1'), ('rec2100-hlg', 'color(rec2100-hlg 0.6 0.55 0.5)', 'HDR 8.2'),
    ('rec2100-linear', 'color(rec2100-linear 2.5 2.25 2)', 'HDR 8.3'), ('ictcp', 'ictcp(0.45 -0.05 0.03)', 'HDR 6.3'),
    ('jzazbz', 'jzazbz(0.12 0.02 -0.03)', 'HDR 6.4'), ('jzczhz', 'jzczhz(0.12 0.04 300)', 'HDR 6.5'),
    ('color-mix', 'color-mix(in oklab, #336699 30%, color(display-p3 0.9 0.6 0.1))', 'C5 3'),
    ('color-mix-hue', 'color-mix(in oklch longer hue, oklch(0.6 0.15 20), oklch(0.7 0.12 200))', 'C5 3, C4 13.5'),
    ('color-mix-three', 'color-mix(in srgb-linear, red, lime 25%, blue 25%)', 'C5 3.3'),
    ('relative-oklch', 'oklch(from #336699 calc(l + 0.1) calc(c * 1.5) calc(h + 30))', 'C5 4.9'),
    ('relative-color', 'color(from color(display-p3 0.4 0.5 0.6) display-p3 calc(r * 0.9) g calc(b + 0.05))', 'C5 5.1'),
    ('alpha', 'alpha(from color(display-p3 0.4 0.5 0.6) / 0.5)', 'C5 4.10'),
    ('device-cmyk', 'device-cmyk(10% 20% 30% 5% / 80%)', 'C5 6'),
    ('contrast-color', 'contrast-color(color(display-p3 0.2 0.3 0.4))', 'C5 8'),
]
INVALID = [('unknown-space', 'color(profoto-rgb 0.4835 0.9167 0.2188)'), ('bad-component', 'lab(50% 40 abc)'),
           ('legacy-none', 'rgb(none, 20, 30)'), ('commas-in-color', 'color(srgb, 1, 0, 0)'),
           ('mix-negative', 'color-mix(in srgb, red -10%, blue)'), ('hdr-same-headroom', 'color-hdr(red 1, blue 1)')]
# targets: (row suffix, QImage format, QColorSpace::NamedColorSpace or none, extended range)
TARGETS = [('rgba64', 'Format_RGBA64', None, False), ('rgba64-p3', 'Format_RGBA64', 'DisplayP3', False),
           ('rgba32f', 'Format_RGBA32FPx4', None, True), ('rgba32f-2020', 'Format_RGBA32FPx4', 'Bt2020', True)]
SPACE = {None: 'srgb', 'DisplayP3': 'display-p3', 'Bt2020': 'rec2020'}
RENDER = ['color(srgb 0.123457 0.654321 0.876543)', 'lab(52.2345% 40.1645 59.9971)', 'oklch(0.7 0.3 145)',
          'color(display-p3 1 0.25 0)', 'color(rec2100-linear 2.5 2.25 2)', 'color(rec2100-pq 0.5 0.45 0.4)']


def cnum(v):
    return 'qQNaN()' if v is None else repr(float(v))


# light-dark() and the element color scheme (CSS Color 5 section 7, CSS Color Adjustment 1 sections 2.2 to 2.4):
# (row name, the SVG body around a 4x4 rect whose fill is FILL, the preference, the fill)
LD = 'light-dark(color(srgb 0.2 0.4 0.6), color(srgb 0.8 0.6 0.4))'
RECT = '<rect width="4" height="4" style="fill: %s"/>'
SCHEME = [
    ('no color-scheme, no preference', None, RECT, None, LD),
    ('no color-scheme, dark preference', None, RECT, 'dark', LD),
    ('light, dark preference', 'light', RECT, 'dark', LD),
    ('dark, no preference', 'dark', RECT, None, LD),
    ('dark, light preference', 'dark', RECT, 'light', LD),
    ('light dark, no preference', 'light dark', RECT, None, LD),
    ('light dark, light preference', 'light dark', RECT, 'light', LD),
    ('light dark, dark preference', 'light dark', RECT, 'dark', LD),
    ('dark light, no preference', 'dark light', RECT, None, LD),
    ('only light, dark preference', 'only light', RECT, 'dark', LD),
    ('only dark, light preference', 'dark only', RECT, 'light', LD),
    ('custom ident only, dark preference', 'foo', RECT, 'dark', LD),
    ('inherited from a group', 'dark', '<g>' + RECT + '</g>', None, LD),
    ('normal under a dark group', None, '<g style="color-scheme: dark"><rect width="4" height="4" '
     'style="color-scheme: normal; fill: %s"/></g>', None, LD),
    ('nested in color-mix()', 'dark', RECT, None, 'color-mix(in srgb, %s, white 25%%)' % LD),
    ('from a style sheet', None, '<style>rect { color-scheme: dark }</style>' + RECT, None, LD),
]
PREF = {None: 'None', 'light': 'Light', 'dark': 'Dark'}
# contrast-color() (CSS Color 5 section 8): backgrounds where the choice differs from plain WCAG 2.1, one where the
# 3:1 floor overrides the lightness choice, and ones where both agree
CONTRAST = ['#e74c3c', '#3498db', '#808080', '#ff0000', 'oklch(0.65 0.15 250)', '#ff6600', 'oklch(0.75 0.1 100)',
            'color(display-p3 0.2 0.3 0.4)', 'oklch(0.6 0.25 145)']


def scheme_rows():
    for name, root, body, pref, fill in SCHEME:
        # the color-scheme that applies to the rect: the root's, inherited, unless the body sets its own
        applies = root
        if 'color-scheme: normal' in body:
            applies = None
        elif 'rect { color-scheme: ' in body:
            applies = body.split('rect { color-scheme: ')[1].split(' }')[0]
        computed = None if applies is None else ref.parse_color_scheme(applies)
        dark = ref.element_color_scheme(computed, pref) == 'dark'
        c = ref.parse(fill, ref.Context(dark=dark))
        rgb, alpha, mapped = ref.target_value(c, 'srgb', True)
        open_tag = '<svg xmlns=\\"http://www.w3.org/2000/svg\\" width=\\"4\\" height=\\"4\\"%s>' % (
            '' if root is None else ' style=\\"color-scheme: %s\\"' % root)
        svg = open_tag + (body % fill).replace('"', '\\"') + '</svg>'
        yield name, svg, PREF[pref], rgb


def main():
    print('// Copyright (C) 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>')
    print('// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only')
    print('')
    print("// Expected values computed with the specifications' own sample code (CSS Color 4")
    print('// section 19, CSS Color HDR section 11); regenerate them rather than edit by hand.')
    print('static const struct { const char *name; const char *css; const char *space; double c[3]; double alpha; } parseRows[] = {')
    for name, css, clause in PARSE:
        c = ref.parse(css, ref.Context(current=ref.rgb8(0)))
        print('    {"%s (%s)", "%s", "%s", {%s}, %s},' % (name, clause, css, c.space, ', '.join(cnum(v) for v in c.c), cnum(c.alpha)))
    print('};')
    print('static const struct { const char *name; const char *css; } invalidRows[] = {')
    for name, css in INVALID:
        print('    {"%s", "%s"},' % (name, css))
    print('};')
    print('static const struct { const char *name; const char *css; QImage::Format format; int space; double rgb[3]; bool mapped; } renderRows[] = {')
    for css in RENDER:
        for suffix, fmt, cs, ext in TARGETS:
            c = ref.parse(css)
            rgb, alpha, mapped = ref.target_value(c, SPACE[cs], not ext)
            print('    {"%s %s", "%s", QImage::%s, %s, {%s}, %s},' % (
                css.split('(')[0] + ('-' + css.split()[0].split('(')[1] if css.startswith('color(') else ''), suffix, css, fmt,
                ('QColorSpace::%s' % cs) if cs else '-1', ', '.join(repr(v) for v in rgb), 'true' if mapped else 'false'))
    print('};')
    print('static const struct { const char *name; const char *svg; QSvgCssColorSchemePreference preference; double rgb[3]; } schemeRows[] = {')
    for name, svg, pref, rgb in scheme_rows():
        print('    {"%s", "%s", QSvgCssColorSchemePreference::%s, {%s}},' % (name, svg, pref, ', '.join(repr(v) for v in rgb)))
    print('};')
    print('static const struct { const char *background; bool black; bool wcagBlack; double ratio; } contrastRows[] = {')
    for css in CONTRAST:
        pick, wcag, lightness, ratio = ref.contrast_choice(ref.parse(css))
        print('    {"%s", %s, %s, %r},  // Oklab L %.4f' % (css, 'true' if pick == 'black' else 'false',
                                                       'true' if wcag == 'black' else 'false', ratio, lightness))
    print('};')


if __name__ == '__main__':
    main()
