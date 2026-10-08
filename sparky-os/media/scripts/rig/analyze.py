#!/usr/bin/env python3
# usage: analyze.py <rundir> <screen width>
# Per capture: mono or stereo, and per view the frame number (16 blocks), the colour of the background and the position of the picture.
# Then the declaration requests from the Wayland log: create / set_content / destroy, with their times against the captures.
import sys, os, re, json, numpy as np
from PIL import Image
d = sys.argv[1]; SW = int(sys.argv[2]) if len(sys.argv) > 2 else 1280

def mask(a, f): return f(a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int))
green = lambda r, g, b: (g > 150) & (r < 100) & (b < 100)
yellow = lambda r, g, b: (r > 180) & (g > 180) & (b < 100)
def bbox(m):
    ys, xs = np.nonzero(m)
    return None if len(xs) < 20 else (xs.min(), ys.min(), xs.max(), ys.max())

def eye(a):
    m = bbox(mask(a, lambda r, g, b: (r > 200) & (b > 200) & (g < 80)))
    if m is None: return None
    x0, y0, wv, hv = int(m[0]), int(m[1]), int(m[2] - m[0] + 1), int(m[3] - m[1] + 1)
    bits = 0
    for i in range(16):
        px = a[int(y0 + hv / 16), int(x0 + (i + .5) * wv / 16)]
        bits = bits * 2 + (1 if px[0] > 128 and px[1] > 128 and px[2] > 128 else 0)
    c = a[int(y0 + hv * .2), int(x0 + wv * .5)]
    colour = 'red' if (c[0] > 150 and c[2] < 100) else 'blue' if (c[2] > 150 and c[0] < 100) else 'grey' if abs(int(c[0]) - int(c[1])) < 20 and abs(int(c[1]) - int(c[2])) < 20 else 'other'
    return dict(frame=bits, colour=colour, rect=(x0, y0, wv, hv))

teal = lambda r, g, b: (r < 40) & (g > 140) & (b > 140) & (abs(g - b) < 30)
FULL = os.environ.get('FULL') == '1'
def place(a, e):
    # margins of the picture inside the window (the window is painted teal; fullscreen: the screen)
    m = bbox(mask(a, lambda r, g, b: (r > 200) & (b > 200) & (g < 80)))
    if m is None: return None
    x, y, w, h = int(m[0]), int(m[1]), int(m[2] - m[0] + 1), int(m[3] - m[1] + 1)
    if FULL: wx0, wy0, wx1, wy1 = 0, 0, a.shape[1], a.shape[0]
    else:
        t = bbox(mask(a, teal))
        if t is None: return None
        wx0, wy0, wx1, wy1 = min(t[0], x), min(t[1], y), max(t[2] + 1, x + w), max(t[3] + 1, y + h)
    ml, mr, mt, mb = x - wx0, wx1 - (x + w), y - wy0, wy1 - (y + h)
    return dict(window=(int(wx0), int(wy0), int(wx1 - wx0), int(wy1 - wy0)), pic=(int(x), int(y), int(w), int(h)), margins=(int(ml), int(mr), int(mt), int(mb)),
                centre_err=(round((ml - mr) / 2, 1), round((mt - mb) / 2, 1)))
info = json.load(open(d + '/caps.json'))
rows = []
for c in info['caps']:
    a = np.array(Image.open('%s/c%02d.png' % (d, c['i'])).convert('RGB')); h, w = a.shape[:2]
    if w == 2 * SW: kind = 'stereo'; eyes = [a[:, :SW], a[:, SW:]]
    else: kind = 'mono'; eyes = [a]
    e = [eye(x) for x in eyes]
    pl = [place(x, y) if y else None for x, y in zip(eyes, e)]
    rows.append(dict(i=c['i'], kind=kind, tod=c['tod'], eyes=e, place=pl))
# declaration requests
reqs = []
for l in open(d + '/mpv.log', errors='replace'):
    m = re.search(r'\[(\d+):(\d+):([\d.]+)\].*-> (kde_stereo_content\w*)#(\d+)\.(\w+)\(([^)]*)\)', l)
    if m: reqs.append((int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)), m.group(4), m.group(6), m.group(7)))
decl = [r for r in reqs if r[1] == 'kde_stereo_content_v1']
mgr = [r for r in reqs if r[1] != 'kde_stereo_content_v1']
creates = [r for r in mgr if r[2] == 'create']
sets = [r for r in decl if r[2] == 'set_content']; destroys = [r for r in decl if r[2] == 'destroy']
kill = info['kill_tod']
destroys_before_end = [r for r in destroys if r[0] < kill - 1.5]
out = dict(first_decl_s=round(decl[0][0] - info['t0_tod'], 2) if decl else None, decl_events=[(round(r[0] - info['t0_tod'], 2), r[2], r[3]) for r in decl], captures=[], creates=len(creates), set_content=len(sets), set_values=sorted(set(r[3] for r in sets)), destroys=len(destroys), destroys_before_end=len(destroys_before_end),
           destroy_times_vs_kill_s=[round(r[0] - kill, 2) for r in destroys])
for r in rows:
    f = [e['frame'] if e else None for e in r['eyes']]; col = [e['colour'] if e else None for e in r['eyes']]
    out['captures'].append(dict(i=r['i'], t=round(r['tod'] - info['t0_tod'], 2), kind=r['kind'], frames=f, colours=col, rect=[e['rect'] if e else None for e in r['eyes']], place=r['place']))
json.dump(out, open(d + '/analysis.json', 'w'), indent=1)
for c in out['captures']: print(c['i'], c['t'], c['kind'], c['frames'], c['colours'], c['rect'][0], ' '.join('E%d window=%s margins=%s centre_err=%s' % (k, p['window'], p['margins'], p['centre_err']) for k, p in enumerate(c['place']) if p))
print({k: v for k, v in out.items() if k not in ('captures',)})
