#!/usr/bin/env python3
"""analyze_p3.py <window.png> x y w h  : a KWin stereo window capture (full side by side, left eye first) and the canvas rectangle (in one eye's pixels).
Prints per eye the colour counts inside the canvas, the differing pixels between the eyes inside and outside the canvas, the eye width."""
import sys, numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int)
x, y, w, h = map(int, sys.argv[2:6])
H, W2 = a.shape[:2]; W = W2 // 2
L, R = a[:, :W], a[:, W:]
diff = (L != R).any(axis=2)
inside = np.zeros_like(diff); inside[y:y+h, x:x+w] = True
def cls(e):
    r, g, b = e[..., 0], e[..., 1], e[..., 2]
    return dict(red=(r > 150) & (g < 80) & (b < 80), blue=(b > 150) & (r < 80) & (g < 80), white=(r > 200) & (g > 200) & (b > 200))
print('capture %dx%d, one eye %dx%d' % (W2, H, W, H))
for name, e in (('left', L), ('right', R)):
    c = cls(e); print('%s eye, canvas rect: red %d, blue %d, white %d (of %d)' % (name, (c['red'] & inside).sum(), (c['blue'] & inside).sum(), (c['white'] & inside).sum(), w * h))
print('differing pixels outside the canvas rect: %d' % (diff & ~inside).sum())
print('differing pixels inside the canvas rect: %d of %d' % ((diff & inside).sum(), w * h))
ys, xs = np.where(diff)
if len(ys): print('bbox of all differing pixels: x %d..%d y %d..%d (rect x %d..%d y %d..%d)' % (xs.min(), xs.max(), ys.min(), ys.max(), x, x + w - 1, y, y + h - 1))
