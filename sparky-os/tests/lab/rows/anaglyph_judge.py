#!/usr/bin/python3 -I
"""anaglyph_judge.py RESULTS [VARIANT...]: judges the anaglyph steps (rig/guest/anaglyph-steps.sh). The declared test client has a blue
2D window and a 3D area whose left view is red (255,0,0) and whose right view is green (0,255,0). The frame of a variant holds the
anaglyph when the area's colour equals the modern Dubois mix of the two views, encode(Ml*decode(L)+Mr*decode(R)) with gamma 2.2 as
Stereo KWin's output filter does (the sets are the bench's analyze-eyeorder.py), within 2 codes; the control is the left view
alone, pure red. Prints every variant's area colour. Exit 0 when every variant named holds (no names: all but plain, file and filemode,
that is doctor), 1 when one does not, 77 when the guest did not finish, 2 a crash."""
import os
import sys
import traceback


def _crash(*a):
    traceback.print_exception(*a)
    os._exit(2)


sys.excepthook = _crash
from collections import Counter
from PIL import Image

results = sys.argv[1]
want = sys.argv[2:] or ["doctor"]
run = os.path.dirname(os.path.abspath(results))
lines = [l.strip() for l in open(results, errors="replace") if l.startswith("STEREO|")]
if not any(l.startswith("STEREO|anaglyph|done") for l in lines):
    print("SKIP: the anaglyph steps did not finish (the guest or the compositor did not start): %s" % "; ".join(lines[-3:]))
    sys.exit(77)
MODERN = ([[0.4154, 0.4710, 0.1669], [-0.0458, -0.0484, -0.0257], [-0.0547, -0.0615, 0.0128]],
          [[-0.0109, -0.0364, -0.0060], [0.3756, 0.7333, 0.0111], [-0.0651, -0.1287, 1.2971]])


def mix(L, R):
    out = []
    for i in range(3):
        v = sum(MODERN[0][i][j] * (L[j] / 255.0) ** 2.2 for j in range(3)) + sum(MODERN[1][i][j] * (R[j] / 255.0) ** 2.2 for j in range(3))
        v = min(max(v, 0.0), 1.0) ** (1 / 2.2)
        out.append(int(round(v * 65535)) // 256)
    return tuple(out)


expect = mix((255, 0, 0), (0, 255, 0))
window = mix((0, 0, 255), (0, 0, 255))  # the blue 2D window, the same in both eyes, under the same filter
ok = True
for v in ("plain", "file", "filemode", "doctor"):
    p = next((q for q in (os.path.join(run, v + ".ppm"), os.path.join(run, v + ".png")) if os.path.exists(q)), None)
    if not p:
        print("%-9s no frame" % v)
        ok = ok and v not in want
        continue
    im = Image.open(p).convert("RGB")
    colours = Counter()
    for n, c in im.getcolors(1 << 24):
        if c not in ((0, 0, 0), (0, 0, 255), window):
            colours[c] += n
    area = colours.most_common(1)[0] if colours else (None, 0)
    good = area[0] is not None and all(abs(a - b) <= 2 for a, b in zip(area[0], expect))
    wpix = sum(n for n, c in im.getcolors(1 << 24) if c == window)
    print("%-9s the 3D area is %s over %d pixels: %s (the anaglyph mix is %s, the left view alone (255, 0, 0)); the 2D window is %s" % (
        v, area[0], area[1], "the anaglyph" if good else "not the anaglyph", expect,
        "colour coded to %s over %d pixels" % (window, wpix) if wpix else "blue, not colour coded"))
    if v in want:
        ok = ok and good
sys.exit(0 if ok else 1)
