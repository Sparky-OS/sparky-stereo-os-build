#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""compare.py A.png B.png -- how many pixels differ between two captures of the same size, as JSON."""
import json
import sys

import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.int16)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB")).astype(np.int16)
out = {"a": list(a.shape), "b": list(b.shape)}
if a.shape == b.shape:
    diff = np.abs(a - b).max(axis=2) > 0
    ys, xs = np.nonzero(diff)
    out["differing"] = int(diff.sum())
    out["box"] = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None
print(json.dumps(out))
