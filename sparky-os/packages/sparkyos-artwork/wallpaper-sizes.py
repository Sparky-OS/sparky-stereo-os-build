#!/usr/bin/env python3
# Made by Claude Sonnet 5.5 for Daniel Ramos (Capitain Jack) 2026/11/09 (ORDER 456)
# Copyright 2026 under the GNU GPL3 License
# Makes the smaller sizes of a Plasma wallpaper package's picture, the sizes Plasma's Image wallpaper chooses from
# (WallpaperPackage::findPreferredImageInPackage reads the width and height from the file names in contents/images).
# Every size is a downscale of the one source picture with Lanczos, never an upscale, the 16:9 composition unchanged;
# the source stays in the package as it is. Each output is read back and compared with an area-average
# reduction of the source (a different filter): the mean absolute difference must stay under LIMIT levels of 255.
# Usage: wallpaper-sizes.py SOURCE.png IMAGES_DIR [WxH ...]
import os
import sys
from PIL import Image

SIZES = ((1280, 720), (1366, 768), (1600, 900), (1920, 1080), (2560, 1440))
LIMIT = 1.5


def mean_abs_difference(a, b):
    from PIL import ImageChops, ImageStat
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def make(source, images, sizes):
    src = Image.open(source)
    src.load()
    if src.mode != 'RGB':
        sys.exit('%s: mode %s, only RGB is made by this script' % (source, src.mode))
    made = []
    for w, h in sizes:
        if w >= src.width or h >= src.height:
            sys.exit('%s: %dx%d is not smaller than the source %dx%d, a size is never upscaled' % (source, w, h, src.width, src.height))
        if src.width * h != src.height * w and abs(src.width / src.height - w / h) > 0.001:
            sys.exit('%dx%d does not keep the source composition (%dx%d)' % (w, h, src.width, src.height))
        out = os.path.join(images, '%dx%d.png' % (w, h))
        if os.path.lexists(out):
            sys.exit('%s exists: a size is made once' % out)
        small = src.resize((w, h), Image.LANCZOS)
        small.save(out, optimize=True, compress_level=9)
        back = Image.open(out)
        back.load()
        if back.size != (w, h) or back.mode != 'RGB':
            sys.exit('%s: read back %s %s' % (out, back.size, back.mode))
        if list(back.tobytes()) != list(small.tobytes()):
            sys.exit('%s: the file differs from the picture made' % out)
        reference = src.resize((w, h), Image.BOX)
        diff = mean_abs_difference(back, reference)
        if diff > LIMIT:
            sys.exit('%s: mean difference %.3f from the area-average reduction of the source, over %.1f' % (out, diff, LIMIT))
        made.append((out, diff))
    return made


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sizes = SIZES
    if len(sys.argv) > 3:
        sizes = tuple(tuple(int(n) for n in s.split('x')) for s in sys.argv[3:])
    for out, diff in make(sys.argv[1], sys.argv[2], sizes):
        print('%s: %d bytes, mean difference from the area-average reduction %.3f of 255' % (out, os.path.getsize(out), diff))


if __name__ == '__main__':
    main()
