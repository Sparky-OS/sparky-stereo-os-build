#!/usr/bin/env python3
# usage: ana2.py <png>...  : per capture mono/stereo, per-eye mean colour of the video centre, frame numbers (eye_info), differing pixels between eyes outside the video rectangle
import sys, os, numpy as np
src = open('/p/layers.py').read().split("sw = int(os.environ")[0]
ns = {}; exec(compile(src, 'layers', 'exec'), ns)
_ei = ns['eye_info']
def ei(e):
    try: return _ei(e)
    except Exception: return None
from PIL import Image
sw = int(os.environ.get('SW_W', 1280))
for f in sys.argv[1:]:
    a = np.array(Image.open(f).convert('RGB')); h, w = a.shape[:2]
    name = os.path.basename(os.path.dirname(f)) + '/' + os.path.basename(f)
    eyes = [a[:, :sw], a[:, sw:]] if w == 2 * sw else [a]
    kind = 'stereo' if len(eyes) == 2 else 'mono'
    top = int(os.environ.get('CROP_TOP', 0))   # rows of a window's title bar, whose icon is green
    def masked(e):
        e = e.copy(); e[:top] = 0; return e
    v = [ei(masked(e)) for e in eyes]
    vf = [x['frame'] if x else None for x in v]; vc = [x['colour'] if x else None for x in v]
    rect = v[0]['rect'] if v[0] else None
    extra = ''
    if kind == 'stereo':
        d = np.any(eyes[0].astype(int) != eyes[1].astype(int), axis=2)
        if rect:
            x0, y0, rw, rh = rect
            x0, y0, rw, rh = max(0,x0-6), max(0,y0-6), rw+12, rh+12   # the rectangle is estimated from the blocks, a few pixels off
            inside = d[y0:y0 + rh, x0:x0 + rw].sum(); outside = int(d.sum() - inside)
        else: outside = int(d.sum())
        bar = int(d[710:770, 40:1240].sum()) if not os.environ.get('NO_BAR') else -1
        extra = ' outside_video_differ=%d controls_differ=%d' % (outside, bar)
    ok = None not in vf and len(set(vf)) == 1
    print('%s %s frame=%s colour=%s rect=%s %s%s' % (name, kind, vf, vc, rect, 'FRAMES-EQUAL' if ok else 'FRAMES-DIFFER', extra))
