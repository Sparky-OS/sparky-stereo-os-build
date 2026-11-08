#!/usr/bin/python3
# The splash stays inside the desktop's own depth limits at the same eye width (ORDER 472).
# usage: depth-limits.py GENERATED.script
# Stereo KWin (src/scene/stereodepth.cpp): a level's parallax is lround(limit * viewWidth / 1920), the limits being
# kwinrc [StereoDepth] PoppedLimit 4 and SunkLimit 10 by default. The script's own placement (SS_Place) is modelled
# here with the same rounding: the whole disparity is d rounded to a pixel, the odd pixel to the left eye.
import math, re, sys

POPPED, SUNK, REF = 4.0, 10.0, 1920.0
text = open(sys.argv[1], encoding='utf-8').read()

def const(name):
    m = re.search(r'^%s = ([A-Z_0-9.]+)(?: \* ([A-Z_0-9.]+))?;' % name, text, re.M)
    if not m:
        raise SystemExit('constant not found: ' + name)
    def val(t):
        return float(t) if re.match(r'[0-9.]+$', t) else const(t)
    return val(m.group(1)) * (val(m.group(2)) if m.group(2) else 1)

def lround(v):
    return int(math.floor(abs(v) + 0.5)) * (1 if v >= 0 else -1)

def disparity(d):
    """the disparity the script's SS_Place gives: left eye shift minus right eye shift"""
    if 'whole = Math.Int (d + 0.5)' in text:
        whole = int(d + 0.5) if d >= 0 else -int(-d + 0.5)
        left = int(whole / 2 + 0.5)
        return left - (left - whole)
    half = d / 2
    return int(half + 0.5) - int(-half + 0.5)   # the old placement: both eyes round their half

pop, sink, base, logo = const('POP_PX'), const('SINK_PX'), const('BASE_PX'), const('LOGO_PX')
failed = 0
for w in (1366, 1280, 1920, 2560, 3840):
    scale = w / REF
    desk_pop, desk_sunk = lround(POPPED * scale), lround(SUNK * scale)
    pops = {'base': base, 'logo': logo, 'electron at its nearest': base + pop}
    for name, v in pops.items():
        got = disparity(v * scale)
        ok = got <= desk_pop
        failed += not ok
        print('%5d  %-24s splash %2d px  desktop popped limit %2d px  %s' % (w, name, got, desk_pop, 'ok' if ok else 'ABOVE'))
    got = -disparity((base - sink) * scale) if base - sink < 0 else 0
    ok = got <= desk_sunk
    failed += not ok
    print('%5d  %-24s splash %2d px  desktop sunk limit   %2d px  %s' % (w, 'electron at its farthest', got, desk_sunk, 'ok' if ok else 'ABOVE'))
    if w < 1500:
        ok = disparity(logo * scale) > disparity(base * scale)
        failed += not ok
        print('%5d  %-24s logo %d px against base %d px  %s' % (w, 'levels stay apart', disparity(logo * scale), disparity(base * scale), 'ok' if ok else 'COLLAPSED'))
print('%d failing' % failed)
sys.exit(1 if failed else 0)
