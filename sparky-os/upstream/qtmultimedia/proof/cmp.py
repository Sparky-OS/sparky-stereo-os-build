import sys, numpy as np
from PIL import Image
# usage: cmp.py <a.png> <b.png> : differing pixels of the whole capture, and in the video area (rows 40-699: the window's text rows are left out)
a = np.array(Image.open(sys.argv[1]).convert('RGB')).astype(int); b = np.array(Image.open(sys.argv[2]).convert('RGB')).astype(int)
if a.shape != b.shape: print('shape differs', a.shape, b.shape); sys.exit(1)
d = np.abs(a - b).max(axis=2)
v = d[40:700]
print('whole window %d of %d pixels differ (largest %d); video area %d of %d (largest %d)' % ((d > 0).sum(), d.size, d.max(), (v > 0).sum(), v.size, v.max()))
