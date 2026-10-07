#!/usr/bin/env python3
"""float items over a backdrop that differs between the eyes: are the differing pixels inside an item's rectangle only those of the
backdrop (the same scene without the items)?  usage: subset.py with-items.png without-items.png probe-with.json"""
import json, sys, numpy as np
from PIL import Image
a = np.array(Image.open(sys.argv[1]).convert('RGBA')); b = np.array(Image.open(sys.argv[2]).convert('RGBA'))
p = json.load(open(sys.argv[3]))
W = a.shape[1] // 2
da = np.any(a[:, :W] != a[:, W:], axis=2); db = np.any(b[:, :W] != b[:, W:], axis=2)
for it in p['float_items']:
    x, y, w, h = [int(round(v)) for v in it['rect']]
    sa, sb = da[y:y + h, x:x + w], db[y:y + h, x:x + w]
    extra = int((sa & ~sb).sum())
    print(f"{it['name']}: differing with the item {int(sa.sum())}, backdrop alone {int(sb.sum())}, differing only because of the item {extra}")
