#!/usr/bin/env python3
# usage: ana.py <png>...   (SW_W = screen width, default 1280)
# Per capture: mono or stereo (a screen twice as wide holds the left eye, then the right eye); per eye the frame number written
# into the video (16 blocks), the colour of the view (LEFT red, RIGHT blue) and the video's rectangle; for stereo the count of pixels
# that differ between the eyes outside the video's rectangle (the window's own part must be identical in both eyes).
import sys, os, numpy as np
src = open('/p/layers.py').read().split("sw = int(os.environ")[0]
ns = {}; exec(compile(src, 'layers', 'exec'), ns)
_eye_info = ns['eye_info']
def eye_info(e):
    # a picture that is not one clean view (an undeclared packed video shown as it is) has no frame number to read
    try: return _eye_info(e)
    except Exception: return None
from PIL import Image
sw = int(os.environ.get('SW_W', 1280))
for f in sys.argv[1:]:
    a = np.array(Image.open(f).convert('RGB')); h, w = a.shape[:2]
    name = os.path.basename(os.path.dirname(f)) + '/' + os.path.basename(f)
    eyes = [a[:, :sw], a[:, sw:]] if w == 2 * sw else [a]
    kind = 'stereo' if len(eyes) == 2 else 'mono'
    v = [eye_info(e) for e in eyes]
    vf = [x['frame'] if x else None for x in v]; vc = [x['colour'] if x else None for x in v]
    rect = [x['rect'] if x else None for x in v]
    extra = ''
    if kind == 'stereo':
        d = np.any(eyes[0].astype(int) != eyes[1].astype(int), axis=2)
        ys, xs = np.nonzero(d)
        if len(xs):
            bb = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
            outside = int(d.sum() - d[bb[1]:bb[3] + 1, bb[0]:bb[2] + 1].sum())
        else: bb, outside = None, 0
        extra = ' eyes_differ_bbox=%s outside=%d' % (bb, outside)
    ok = None not in vf and len(set(vf)) == 1
    print('%s %s video=%s colour=%s rect=%s %s%s' % (name, kind, vf, vc, rect[0], 'FRAMES-EQUAL' if ok else 'FRAMES-DIFFER', extra))
