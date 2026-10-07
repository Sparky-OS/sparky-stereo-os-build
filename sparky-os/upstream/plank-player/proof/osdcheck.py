#!/usr/bin/env python3
# usage: osdcheck.py <png>...: for a stereo capture (left eye, right eye side by side) the number of pixels that differ between the eyes in the
# strip of the on-screen display (the bottom 10% of the screen, Plank Player's OSD height) and in the whole window outside the video's rows
import sys, numpy as np
from PIL import Image
for f in sys.argv[1:]:
    a = np.array(Image.open(f).convert('RGB')).astype(int); h, w = a.shape[:2]
    if w < 2000:
        print('%s: mono capture' % f.split('/')[-2]); continue
    e0, e1 = a[:, :w // 2], a[:, w // 2:]
    top = int(h * 0.9)
    d = np.any(e0 != e1, axis=2)
    print('%s strip rows %d-%d: %d of %d pixels differ between the eyes; strip is not black: %s' % (f.split('/')[-2] + '/' + f.split('/')[-1], top, h - 1, int(d[top:].sum()), d[top:].size, bool((e0[top:] > 40).any())))
