#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check a raw X11 image from d3d9-pair.c; this is not a compositor oracle."""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


SIZES = ((320, 200), (256, 160))


def compare(pixels, phase, stereo):
    width, height = SIZES[phase]
    if pixels.shape != (height, width, 3):
        raise ValueError(f'Expected {width}x{height} RGB, got {pixels.shape}')
    y, x = np.indices((height, width))
    eye = x // (width // 2) if stereo else np.zeros_like(x)
    local_x = x % (width // 2) if stereo else x
    expected = np.stack((local_x & 255, height - 1 - y,
                         (eye << 7) | ((local_x >> 8) << 3)), axis=2).astype(np.uint8)
    error = np.abs(pixels.astype(np.int16) - expected.astype(np.int16))
    wrong = np.any(error != 0, axis=2)
    return {'phase': phase, 'mode': 'stereo' if stereo else 'mono',
            'width': width, 'height': height, 'pixels': width * height,
            'wrong_pixels': int(wrong.sum()), 'max_channel_error': int(error.max()),
            'wrong_channels': [int(np.count_nonzero(error[:, :, c])) for c in range(3)],
            'status': 'FAIL' if wrong.any() else 'PASS'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--phase', type=int, choices=(0, 1), required=True)
    parser.add_argument('--mode', choices=('mono', 'stereo'), required=True)
    args = parser.parse_args()
    pixels = np.asarray(Image.open(args.image).convert('RGB'))
    result = compare(pixels, args.phase, args.mode == 'stereo')
    print(json.dumps(result, sort_keys=True))
    return int(result['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
