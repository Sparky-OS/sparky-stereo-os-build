#!/usr/bin/env python3
"""usage: analyze.py <evidence-dir>...  Reads window.png (KWin's capture of the active window, both eyes side by side),
prints per eye: red / blue fraction, where the white text sits, and whether the 2D parts (menu bar) match in both eyes."""
import sys, os, re
import numpy as np
from PIL import Image

def stats(h):
    r, g, b = h[..., 0].astype(int), h[..., 1].astype(int), h[..., 2].astype(int)
    red = (r > 150) & (g < 70) & (b < 70)
    blue = (b > 150) & (r < 70) & (g < 70)
    white = (r > 220) & (g > 220) & (b > 220)
    return red.mean(), blue.mean(), white, red, blue

def box(m):
    ys, xs = np.nonzero(m)
    return None if len(xs) == 0 else (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))

def main(d):
    out = []
    cap = open(os.path.join(d, 'capture.log')).read() if os.path.exists(os.path.join(d, 'capture.log')) else ''
    m = re.findall(r'width=(\d+) height=(\d+) stereo=(\w+)', cap)
    out.append('capture screen/window: ' + ' | '.join('%sx%s stereo=%s' % t for t in m))
    xw = os.path.join(d, 'xwin.txt')
    if os.path.exists(xw):
        t = open(xw).read()
        dm = re.search(r'STEREO_CONTENT\(CARDINAL\) = (\d+)', t)
        out.append('declaration _KDE_NET_WM_STEREO_CONTENT = %s' % (dm.group(1) if dm else 'none'))
    p = os.path.join(d, 'window.png')
    a = np.array(Image.open(p).convert('RGB'))
    H, W, _ = a.shape
    half = W // 2
    L, R = a[:, :half], a[:, half:half * 2]
    out.append('window %dx%d, one eye %dx%d' % (W, H, half, H))
    for name, h in (('left eye ', L), ('right eye', R)):
        rf, bf, white, red, blue = stats(h)
        col = red if rf >= bf else blue
        out.append('%s: red %.3f blue %.3f  dominant=%s  colour box=%s  white px=%d' % (
            name, rf, bf, 'RED' if rf > 0.2 and rf > bf else 'BLUE' if bf > 0.2 else 'none', box(col), white.sum()))
    for name, h in (('left eye ', L), ('right eye', R)):
        yel = (h[..., 0] > 220) & (h[..., 1] > 220) & (h[..., 2] < 80)
        ys, xs = np.nonzero(yel)
        if len(xs): out.append('%s yellow marker: %d px, x mean %.1f (cols %d..%d), y rows %d..%d' % (name, len(xs), xs.mean(), xs.min(), xs.max(), ys.min(), ys.max()))
        else: out.append('%s yellow marker: none visible' % name)
    # menu bar: top 20 rows identical in both eyes?
    top = 20
    same = (L[:top] == R[:top]).all(axis=2).mean()
    out.append('top %d rows (menu bar) identical in both eyes: %.4f of pixels' % (top, same))
    # pixels that differ: bounding box
    diff = (L != R).any(axis=2)
    out.append('pixels differing between eyes: %.3f of the window, box=%s' % (diff.mean(), box(diff)))
    s = '\n'.join(out)
    open(os.path.join(d, 'analysis.txt'), 'w').write(s + '\n')
    print(d); print(s)

for d in sys.argv[1:]:
    try: main(d)
    except Exception as e: print(d, 'ERROR', e)
