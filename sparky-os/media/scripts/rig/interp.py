#!/usr/bin/env python3
# usage: interp.py <rundir> [screenwidth]  -> interp.json + one line per capture
# Per capture, per eye: the picture's rectangle (magenta border), the white marker bar's centroid and mass from the green channel in its band,
# the colour leak (red-background pixels in the right eye, blue-background pixels in the left eye, purple anywhere), mono or stereo.
import sys, json, numpy as np
from PIL import Image
d = sys.argv[1]; SW = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
info = json.load(open(d + '/caps.json')); out = []
mag = lambda a: (a[..., 0] > 200) & (a[..., 2] > 200) & (a[..., 1] < 80)
def bbox(m):
    ys, xs = np.nonzero(m); return None if len(xs) < 20 else (xs.min(), ys.min(), xs.max(), ys.max())
for c in info['caps']:
    a = np.array(Image.open('%s/c%02d.png' % (d, c['i'])).convert('RGB')).astype(int); h, w = a.shape[:2]
    eyes = [a[:, :SW], a[:, SW:]] if w == 2 * SW else [a]
    e = []
    for k, v in enumerate(eyes):
        b = bbox(mag(v))
        if not b: e.append(None); continue
        x0, y0, x1, y1 = b; wv, hv = x1 - x0 + 1, y1 - y0 + 1; sc = wv / (640.0 if wv / hv < 1.2 else 1280.0)
        band = v[int(y0 + hv * .31):int(y0 + hv * .37), x0 + 4:x1 - 3].mean(axis=2).astype(float)    # the marker is white on the neutral band, the same in both eyes
        prof = band.mean(axis=0); prof = np.clip(prof - np.median(prof), 0, None); mass = prof.sum()
        cx = float(((prof * (np.arange(len(prof)) + 4)).sum() / mass) / sc) if mass > 1 else None
        pic = v[y0:y1 + 1, x0:x1 + 1]; r, g, bl = pic[..., 0], pic[..., 1], pic[..., 2]
        red = int(((r > 150) & (g < 100) & (bl < 100)).sum()); blue = int(((bl > 150) & (r < 100) & (g < 100)).sum()); purple = int(((r > 80) & (bl > 80) & (g < 80) & ~((r > 200) & (bl > 200))).sum())
        e.append(dict(rect=(int(x0), int(y0), int(wv), int(hv)), mass=round(float(mass), 1), cx=None if cx is None else round(cx, 2), red=red, blue=blue, purple=purple))
    out.append(dict(i=c['i'], kind='stereo' if len(eyes) == 2 else 'mono', eyes=e))
json.dump(out, open(d + '/interp.json', 'w'))
for o in out: print(o['i'], o['kind'], [(x['cx'], x['mass'], 'r%d b%d p%d' % (x['red'], x['blue'], x['purple'])) if x else None for x in o['eyes']])
