#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""view_equal.py RUN_A RUN_B: compares the render view of two ParaView runs' first captures (left eye when a capture is
two eyes wide). The view is the region the maximized window gives on the rig's 1920x1080 output, inside its blue focus
border; the status bar (a memory figure that changes every run) is outside it. Prints the pixels that differ and the
largest channel difference, as JSON."""
import json, sys
from PIL import Image, ImageChops

BOX = (360, 196, 1910, 1042)


def view(run):
    im = Image.open(f'{run}/shot1.png').convert('RGB')
    if im.width > 1920:
        im = im.crop((0, 0, im.width // 2, im.height))
    return im.crop(BOX)


a, b = view(sys.argv[1]), view(sys.argv[2])
d = ImageChops.difference(a, b)
px = sum(1 for p in d.getdata() if p != (0, 0, 0))
print(json.dumps({'a': sys.argv[1].rstrip('/').split('/')[-1], 'b': sys.argv[2].rstrip('/').split('/')[-1],
                  'box': BOX, 'pixels': a.width * a.height, 'differing': px, 'max_channel_difference': max(max(c) for c in d.getextrema())}))
