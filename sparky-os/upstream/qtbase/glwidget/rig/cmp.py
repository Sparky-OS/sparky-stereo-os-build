#!/usr/bin/env python3
"""usage: cmp.py a.png b.png  -> number of differing pixels (and the sizes)"""
import sys, numpy as np
from PIL import Image
a = np.array(Image.open(sys.argv[1]).convert("RGBA")).astype(int); b = np.array(Image.open(sys.argv[2]).convert("RGBA")).astype(int)
if a.shape != b.shape: print("size differs %s vs %s" % (a.shape, b.shape)); sys.exit(1)
d = (np.abs(a - b).sum(axis=2) > 0)
print("%d differing pixels of %d" % (d.sum(), d.size))
