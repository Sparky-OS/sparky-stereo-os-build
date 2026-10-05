#!/usr/bin/env python3
# usage: sync-check.py <evidence dir>: the frame number in each eye of every capture
import sys, glob
from PIL import Image
X0, Y0, SUB_X, SUB_Y = 352, 220, 64, 48          # window and subsurface on the 1024x640 screen
BITS, BIT_W, BIT_X, BIT_Y, BIT_H = 16, 7, 8, 8, 16
def number(eye):
    n = 0
    for i in range(BITS):
        r, g, b = eye.getpixel((X0 + SUB_X + BIT_X + i * BIT_W + BIT_W // 2, Y0 + SUB_Y + BIT_Y + BIT_H // 2))
        assert (r, g, b) in ((255, 255, 255), (0, 0, 0)), (i, r, g, b)
        n = n * 2 + (r == 255)
    return n
ok = True
for f in sorted(glob.glob(sys.argv[1] + '/shot*.png')):
    im = Image.open(f).convert('RGB'); w, h = im.size
    if w == 2048:
        l, r = number(im.crop((0, 0, 1024, h))), number(im.crop((1024, 0, 2048, h)))
        ok &= l == r
        print(f.split('/')[-1], 'left frame', l, 'right frame', r, 'SAME' if l == r else 'DIFFERENT')
    else:
        print(f.split('/')[-1], 'one image, frame', number(im))
        ok = False
print('in sync' if ok else 'not stereo or not in sync')
sys.exit(0 if ok else 1)
