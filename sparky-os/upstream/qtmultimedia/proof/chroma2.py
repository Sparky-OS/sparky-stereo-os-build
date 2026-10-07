import sys, numpy as np
from PIL import Image
# usage: chroma2.py <axis H|V> <png>... : left eye 1280 columns: of the pixels in a 1x1 red/blue pattern, the share that is (almost) pure red or blue
ax = sys.argv[1]
for f in sys.argv[2:]:
    a = np.array(Image.open(f).convert('RGB')).astype(int)
    v = a[100:700, 100:1180]
    r, g, b = v[..., 0], v[..., 1], v[..., 2]
    pure = ((r > 200) & (g < 60) & (b < 60)) | ((b > 200) & (r < 60) & (g < 60))
    print('%s: %.1f%% of the pixels are pure red or blue' % (f.split('/')[-2], 100 * pure.mean()))
