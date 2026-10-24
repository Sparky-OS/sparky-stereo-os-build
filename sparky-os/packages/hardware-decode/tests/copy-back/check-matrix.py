#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
"""Check a copy-back matrix (run-matrix.sh) against the ORDER 234 rule.

Hardware decoding whose pictures the output uses where they are comes first,
software decoding next, and copying every picture back only by the person's
choice or the machine's record. A 3D video keeps the house format either way:
full side by side, left eye first, the same picture in hardware and software.
Exit 0 when every case holds; the published mpv is expected to fail."""
import argparse
import json
from pathlib import Path
import sys

failures = []


def load(root, name):
    path = root/f'{name}.json'
    return json.loads(path.read_text()) if path.exists() else None


def check(name, ok, detail):
    print(f'{"ok  " if ok else "FAIL"} {name}: {detail}')
    if not ok:
        failures.append(name)


def has(case, mark):
    return any(mark in line for line in case['log'])


def expect(root, name, hwdec, out_format=None, stereo=None, marks=(), absent=()):
    case = load(root, name)
    if case is None:
        check(name, False, 'case missing')
        return
    props = case['properties']
    out = props.get('video-out-params') or {}
    problems = []
    if props.get('hwdec-current') != hwdec:
        problems.append(f'hwdec-current {props.get("hwdec-current")!r}, wanted {hwdec!r}')
    if out_format and out.get('pixelformat') != out_format:
        problems.append(f'output picture {out.get("pixelformat")!r}, wanted {out_format!r}')
    if stereo and out.get('stereo-in') != stereo:
        problems.append(f'output stereo {out.get("stereo-in")!r}, wanted {stereo!r}')
    problems += [f'log lacks "{m}"' for m in marks if not has(case, m)]
    problems += [f'log has "{m}"' for m in absent if has(case, m)]
    check(name, not problems, '; '.join(problems) or f'hwdec {hwdec}, output {out.get("pixelformat")} {out.get("stereo-in")}')


def pixels(path):
    from PIL import Image
    image = Image.open(path)
    return image.size, image.mode, image.tobytes()


def same_picture(root, a, b, other=None):
    other = other or root
    pa, pb = root/f'{a}.png', other/f'{b}.png'
    if not pa.exists() or not pb.exists():
        check(f'{a} = {b}', False, 'screenshot missing')
        return
    ia, ib = pixels(pa), pixels(pb)
    ca, cb = load(root, a)['properties'], load(other, b)['properties']
    shape = (ca.get('dwidth'), ca.get('dheight')) == (cb.get('dwidth'), cb.get('dheight'))
    check(f'{a} = {b}', ia == ib and shape,
          f'{ia[0]} {ia[1]} vs {ib[0]} {ib[1]}, identical pixels {ia[2] == ib[2]}, '
          f'display {ca.get("dwidth")}x{ca.get("dheight")} vs {cb.get("dwidth")}x{cb.get("dheight")}')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('root', type=Path)
    p.add_argument('--none', type=Path, help='the NOGPU=1 run')
    p.add_argument('--before', type=Path, help='the same matrix with the published packages, for picture identity')
    a = p.parse_args()
    r = a.root
    conversion, declared = 'Inserting stereo conversion filter', 'Declaring the 3D video as it is'
    # zero-copy present: hardware first, pictures where they are
    expect(r, 'zc-2d', 'vaapi', out_format='vaapi')
    expect(r, 'zc-sbs', 'vaapi', out_format='vaapi', stereo='sbsl', marks=(declared,), absent=(conversion,))
    expect(r, 'zc-sbs2', 'vaapi', out_format='vaapi', stereo='sbsl', marks=(declared,), absent=(conversion,))
    expect(r, 'gl-2d', 'vaapi', out_format='vaapi')
    expect(r, 'gl-sbs', 'vaapi', out_format='vaapi', stereo='sbsl', marks=(declared,), absent=(conversion,))
    # a packing the CPU rearranges: software rather than copying back, unless the person chose hardware
    expect(r, 'zc-tb', 'no', stereo='sbsl', marks=('Decoding in software: the filters need', conversion))
    expect(r, 'zc-tb-vaapi', 'vaapi', stereo='sbsl', marks=(conversion,))
    expect(r, 'sw-sbs', 'no', stereo='sbsl', marks=(declared,), absent=(conversion,))
    expect(r, 'sw-sbs2', 'no', stereo='sbsl', marks=(declared,), absent=(conversion,))
    expect(r, 'sw-tb', 'no', stereo='sbsl', marks=(conversion,))
    # copy-only, as RADV on the A10's Carrizo: software by default
    for name in ('a10-2d', 'a10-sbs', 'a10-sbs2', 'a10-tb', 'a10-record-no'):
        expect(r, name, 'no', marks=('no DRM modifiers', 'Not copying pictures back'))
    expect(r, 'null-2d', 'no', marks=('Not copying pictures back',))
    # copying back by choice, never removed
    expect(r, 'a10-auto-copy', 'vaapi-copy', stereo='sbsl')
    expect(r, 'a10-vaapi-copy', 'vaapi-copy')
    expect(r, 'a10-record', 'vaapi-copy', stereo='sbsl')
    # the same picture whichever way it was decoded
    same_picture(r, 'zc-sbs', 'sw-sbs')
    same_picture(r, 'zc-sbs2', 'sw-sbs2')
    same_picture(r, 'zc-tb', 'sw-tb')
    same_picture(r, 'a10-sbs', 'sw-sbs')
    if a.before:
        same_picture(r, 'sw-sbs', 'sw-sbs', a.before)
        same_picture(r, 'sw-sbs2', 'sw-sbs2', a.before)
        same_picture(r, 'zc-sbs2', 'sw-sbs2', a.before)
        same_picture(r, 'sw-tb', 'sw-tb', a.before)
    if a.none:
        expect(a.none, 'none-2d', 'no')
        expect(a.none, 'none-sbs', 'no', stereo='sbsl', marks=(declared,))
    print('PASSED' if not failures else f'FAILED: {len(failures)}: {", ".join(failures)}')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
