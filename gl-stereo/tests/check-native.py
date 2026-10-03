# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import runpy
measure = runpy.run_path('measure-quads.py')
p = Path(sys.argv[1])
image_path = sorted(p.glob('*.ppm'))[-1]
left, right, w, h = measure['load_half'](image_path)
result = measure['measure'](left, right, w)
expected = json.loads((p/'expected.json').read_text())
assert left.std() > 10 and right.std() > 10
for name, target in zip(('red','green','blue'), expected):
    measured = result[name]
    assert measured is not None, 'missing colour in an eye'
    print(f"{name}: native eye disparity={measured['dx']:.3f}, expected={target:.3f}")
    assert abs(measured['dx'] - target) <= 1
assert max(abs(v) for v in expected) > 2, 'fixture must exercise stereo'
Image.open(image_path).save(p/'verified.png')
print('PASS: native scientific stereo agrees with application camera geometry')
