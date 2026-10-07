import sys, numpy as np
from PIL import Image
# usage: psnr.py <capture.png> : left eye of the capture (1280x720 at y=40) against the truth and the three reference resizes
pre = sys.argv[2] if len(sys.argv) > 2 else ''
cap = np.array(Image.open(sys.argv[1]).convert('RGB')).astype(float)
eye = cap[40:700, 0:1280]   # not the controls bar over the bottom of the video
def psnr(a, b):
    m = ((a - b) ** 2).mean()
    return 99.0 if m == 0 else 10 * np.log10(255 ** 2 / m)
r = '/w/ref/'
for name in ([pre + 'truth', pre + 'ref-bilinear', pre + 'ref-bicubic', pre + 'ref-lanczos']):
    ref = np.array(Image.open(r + name + ".png").convert("RGB")).astype(float)[:660]
    print('  vs %-13s %.2f dB' % (name, psnr(eye, ref)))
