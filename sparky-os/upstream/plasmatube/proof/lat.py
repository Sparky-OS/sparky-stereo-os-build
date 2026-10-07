#!/usr/bin/env python3
# usage: lat.py <clip> <png>...: the latitude at the centre of the video (mono capture), from the clip's own colours
import sys, os, io, subprocess, numpy as np
from PIL import Image
png = subprocess.run(['ffmpeg', '-v', 'error', '-i', sys.argv[1], '-frames:v', '1', '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True).stdout
src = np.array(Image.open(io.BytesIO(png)).convert('RGB')).astype(float); H = src.shape[0]
table = []
for band in range(-3, 4):
    y = min(max(int(H * (90 - band * 30) / 180), 3), H - 4); table.append((band * 30, src[y - 2:y + 3, 1000:1010].reshape(-1, 3).mean(axis=0)))
for f in sys.argv[2:]:
    a = np.array(Image.open(f).convert('RGB')).astype(float)[297:306, 755:764].reshape(-1, 3).mean(axis=0)
    b = min(table, key=lambda t: np.abs(t[1] - a).sum())
    print(os.path.basename(os.path.dirname(f)) + '/' + os.path.basename(f), 'centre latitude band %+d' % b[0])
