#!/usr/bin/env python3
# usage: ana360.py <kind: 360|180> <clip> <png>...   (SW_W = screen width, default 1280)
# The centre of the video item in each eye (a screen twice as wide is stereo: left eye, right eye): the colour family (LEFT sphere
# reds, RIGHT sphere blues) and the sector it falls in, told as its longitude. The sector colours are read from the clip's own first
# frame (after the encoder), so the match is to what the picture really holds.
import sys, os, subprocess, io, numpy as np
from PIL import Image
kind, clip = sys.argv[1], sys.argv[2]; sw = int(os.environ.get('SW_W', 1280))
CX, CY = int(os.environ.get('CX', 759)), int(os.environ.get('CY', 301))
n, W = (9, 2304) if kind == '360' else (5, 1080)
png = subprocess.run(['ffmpeg', '-v', 'error', '-i', clip, '-frames:v', '1', '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True).stdout
src = np.array(Image.open(io.BytesIO(png)).convert('RGB')).astype(float)
H = src.shape[0]
# LEFT sphere is the top one (360) or the left one (VR180); the sphere is W wide and, for 360 of the stereo clips, W/2 high
sph_h = W // 2 if kind == '360' else W
table = []
for fam, (oy, ox) in (('LEFT', (0, 0)), ('RIGHT', (sph_h, 0) if src.shape[0] > sph_h and kind == '360' else (0, W) if kind == '180' else (0, 0))):
    if fam == 'RIGHT' and kind == '360' and src.shape[0] <= sph_h:
        continue          # a mono clip has the left sphere only
    for i in range(n):
        x = int(ox + (i + .5) * W / n); y = int(oy + sph_h * 0.8)
        c = src[y - 3:y + 4, x - 3:x + 4].reshape(-1, 3).mean(axis=0)
        lon = round(-180 + (i + .5) * 360 / n) if kind == '360' else round(-90 + (i + .5) * 180 / n)
        table.append((fam, lon, c))
def read(eye):
    c = eye[CY - 4:CY + 5, CX - 4:CX + 5].reshape(-1, 3).mean(axis=0)
    best = min(table, key=lambda t: np.abs(t[2] - c).sum())
    return best[0], best[1], float(np.abs(best[2] - c).sum())
for f in sys.argv[3:]:
    a = np.array(Image.open(f).convert('RGB'))
    name = os.path.basename(os.path.dirname(f)) + '/' + os.path.basename(f)
    if a.shape[1] == 2 * sw:
        l, r = read(a[:, :sw]), read(a[:, sw:])
        print('%s stereo left=%s%+d right=%s%+d (colour distance %.0f, %.0f) %s' % (name, l[0], l[1], r[0], r[1], l[2], r[2], 'OK' if (l[0], r[0]) == ('LEFT', 'RIGHT') and l[1] == r[1] else 'WRONG'))
    else:
        l = read(a)
        print('%s mono %s%+d (colour distance %.0f)' % (name, l[0], l[1], l[2]))
