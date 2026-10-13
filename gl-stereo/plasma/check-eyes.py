# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the real compositor capture against starfield's camera-depth oracle."""
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image

path = Path(sys.argv[1])
a = np.array(Image.open(path).convert('RGB'))
assert a.shape in ((720, 2560, 3), (360, 1280, 3)), ('full SBS dimensions', a.shape)
width = a.shape[1] // 2
scale = width / 640
left, right = a[:, :width], a[:, width:]
for eye, pixels in zip(('LEFT', 'RIGHT'), (left, right)):
    assert pixels.max() - pixels.min() > 60, ('empty/uniform', eye)
    Image.fromarray(pixels).save(path.with_name(path.stem + '-' + eye + '.png'))
values = []
for channel, depth in enumerate((6, 10, 20)):
    centers = []
    for eye in (left, right):
        mask = ((eye[:,:,channel] > 60) & (eye[:,:,(channel+1)%3] < 8) &
                (eye[:,:,(channel+2)%3] < 8))
        mask[:, int(200*scale):] = False
        ys, xs = np.where(mask)
        assert 25*scale**2 <= len(xs) <= 64*scale**2, ('missing/occluded marker', channel, len(xs))
        assert np.ptp(ys) < 9*scale and np.ptp(xs) < 9*scale, 'unexpected marker shape'
        centers.append(float(xs.mean()))
    actual = centers[1] - centers[0]
    expected = width * .01 * (1 - 5/depth)
    assert abs(actual - expected) <= 1, (depth, actual, expected)
    values.append(dict(depth=depth, measured_px=actual, expected_px=expected))
if '--prompt' in sys.argv:
    masks = []
    for eye in (left, right):
        roi = eye[390:475, 480:800].astype(int)
        mask = (roi.min(axis=2) > 200) & (np.ptp(roi,axis=2) < 8)
        assert mask.sum() > 1000, 'password field absent'
        masks.append(mask)
    assert np.array_equal(*masks), 'password field differs between eyes'
    values.append(dict(prompt_disparity_px=0, prompt_pixels=int(masks[0].sum())))
print(json.dumps(values, indent=2))
