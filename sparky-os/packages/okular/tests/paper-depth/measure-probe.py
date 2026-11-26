#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Measure the two element directions from the probe's red and green markers."""
import json
import sys

import numpy as np
from PIL import Image

picture = np.asarray(Image.open(sys.argv[1]).convert("RGB"))
assert picture.shape == (1080, 3840, 3), picture.shape
left, right = np.split(picture, 2, axis=1)
result = {}
for name, color in (("behind", (255, 0, 0)), ("in_front", (0, 255, 0))):
    boxes = []
    for eye in (left, right):
        ys, xs = np.nonzero((eye[:420, :800] == color).all(axis=2))
        if len(xs) < 600:
            raise ValueError(f"{name} marker has only {len(xs)} pixels")
        boxes.append([int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())])
    assert boxes[0][1::2] == boxes[1][1::2], boxes
    assert boxes[0][2] - boxes[0][0] == boxes[1][2] - boxes[1][0], boxes
    result[name] = {"shift": boxes[0][0] - boxes[1][0], "boxes": boxes}
print(json.dumps(result))
