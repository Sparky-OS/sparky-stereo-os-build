#!/usr/bin/env python3
# 24 fps clips for the interpolation proofs: 3D side by side (and a 2D one), each view LEFT/RIGHT, blocks with the frame number, magenta border,
# and a white marker bar whose x position is a triangle wave of the frame number (continuous, 20 px per frame, 24 frames up and 24 down).
import subprocess, sys, os
OUT = sys.argv[1]; sys.argv = sys.argv[:2]
exec(open('/w/scripts/mkclips2.py').read().split('N = 150')[0])
from PIL import ImageDraw
W, H = 1280, 720
def mark(im, w, h, n, x0=0):
    d = ImageDraw.Draw(im); k = n % 48; k = k if k < 24 else 48 - k
    d.rectangle([x0, int(h * .27), x0 + w - 1, int(h * .41)], fill=(60, 60, 60))     # the same neutral band behind the marker in both eyes
    x = x0 + 40 + k * 20
    d.rectangle([x, int(h * .30), x + 39, int(h * .38)], fill=(255, 255, 255))
def f3d(n):
    im = Image.new('RGB', (W, H))
    for e, (eye, x0) in enumerate((('L', 0), ('R', W // 2))):
        v = view(W // 2, H, n, eye); mark(v, W // 2, H, n); im.paste(v, (x0, 0))
    return im
def f2d(n):
    im = grey(n); mark(im, W, H, n); return im
def clip(name, fn, n, extra=()):
    p = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', '24', '-i', '-', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '12',
                          '-pix_fmt', 'yuv444p', '-g', '24', '-bf', '0', *extra, '-f', 'matroska', f'{OUT}/{name}.mkv'], stdin=subprocess.PIPE)
    for i in range(n): p.stdin.write(fn(i).tobytes())
    p.stdin.close(); p.wait()
clip('i24-sbs', f3d, 144, ('-metadata:s:v:0', 'stereo_mode=left_right'))
clip('i24-2d', f2d, 144)
def ftb(n):
    im = Image.new('RGB', (W, H))
    for eye, y0 in (('L', 0), ('R', H // 2)):
        v = view(W, H // 2, n, eye); mark(v, W, H // 2, n); im.paste(v, (0, y0))
    return im
clip('i24-tb', ftb, 144, ('-metadata:s:v:0', 'stereo_mode=top_bottom'))
print('done')
