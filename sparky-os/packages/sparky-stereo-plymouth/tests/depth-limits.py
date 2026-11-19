#!/usr/bin/python3
# The splash's levels are the ones the theme had before ORDER 472, from the person's limits, scaled by the screen only.
# usage: depth-limits.py GENERATED.script [POPPED SUNK]
# The script takes the limits from Plymouth (Window.GetStereoPoppedLimit and GetStereoSunkLimit, ORDER 481); the test gives
# it the same two numbers. Daniel, 2026-11-19: "one separation setting, centralized, tailored TO THE SCREEN not to the
# element size". At the display's default limits (popped 4, sunk 10) the levels are those of 20261025: step 4.54, logo 9.08,
# electron pop 4 and sink 6 px at a view 1920 wide; on a screen the eye's width over 1920 scales them (Stereo KWin's
# lround(limit * outputWidth / 1920)), and nothing else: no logo, sprite or element size enters.
import math, re, sys

REF = 1920.0
POPPED, SUNK = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) == 4 else (4.0, 10.0)
text = open(sys.argv[1], encoding='utf-8').read()

def const(name):
    m = re.search(r'^%s = ([^;]+);' % name, text, re.M)
    if not m:
        raise SystemExit('constant not found: ' + name)
    expr = m.group(1).replace('Window.GetStereoPoppedLimit ()', repr(POPPED)).replace('Window.GetStereoSunkLimit ()', repr(SUNK))
    expr = re.sub(r'\b[A-Z][A-Z_0-9]+\b', lambda n: repr(const(n.group(0))), expr)
    if not re.fullmatch(r'[0-9.+\-*/() e]+', expr):
        raise SystemExit('cannot evaluate %s = %s' % (name, m.group(1)))
    return eval(expr)

def disparity(d):
    whole = int(d + 0.5) if d >= 0 else -int(-d + 0.5)
    left = int(whole / 2 + 0.5)
    return left - (left - whole)

pop, sink, base, logo = const('POP_PX'), const('SINK_PX'), const('BASE_PX'), const('LOGO_PX')
failed = 0
def check(ok, what):
    global failed
    failed += not ok
    print('%-4s %s' % ('ok' if ok else 'FAIL', what))

# the levels at the display's default are the pre-472 ones (20261025)
if (POPPED, SUNK) == (4.0, 10.0):
    for name, got, want in (('step', base, 4.54), ('logo', logo, 9.08), ('pop', pop, 4.0), ('sink', sink, 6.0)):
        check(abs(got - want) < 0.01, 'default limits: %s %.3f px, before ORDER 472 %.2f' % (name, got, want))
# they follow the person's limits: popped and sunk in proportion, one rule for every screen
check(abs(logo - 2 * base) < 1e-9 and abs(pop - POPPED) < 1e-9 and abs(sink - 0.6 * SUNK) < 1e-9,
      'the levels follow the limits %g and %g' % (POPPED, SUNK))
# the script scales by the eye's width over 1920 only
for token in ('POP = POP_PX * EYE_W / 1920', 'SINK = SINK_PX * EYE_W / 1920', 'BASE = BASE_PX * EYE_W / 1920', 'LOGO = LOGO_PX * EYE_W / 1920'):
    check(token in text, 'scaled by the eye width only: ' + token)
check(not re.search(r'(LOGO|BASE|POP|SINK)(_PX)?\s*=[^;]*(logo_image|GetHeight|logo_height|GetWidth)', text),
      'no level is computed from the size of a picture')
for w in (1366, 1920, 3840):
    s = w / REF
    print('     %5d wide: base %d px, logo %d px, nearest electron %d px, farthest %d px behind'
          % (w, disparity(base * s), disparity(logo * s), disparity((base + pop) * s), -disparity((base - sink) * s)))
print('%d failing' % failed)
sys.exit(1 if failed else 0)
