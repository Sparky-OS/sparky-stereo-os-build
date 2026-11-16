#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Independent PNG field, pixel and known-disparity checks for native-proof."""
import argparse
import json
from pathlib import Path
import struct
import zlib
import numpy as np
from PIL import Image


def pair(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path
    pos, chunks, mode = 8, [], None
    while pos < len(data):
        length, = struct.unpack_from('>I', data, pos)
        kind = data[pos+4:pos+8]
        body = data[pos+8:pos+8+length]
        crc, = struct.unpack_from('>I', data, pos+8+length)
        assert zlib.crc32(kind+body) == crc, (path, kind, 'CRC')
        chunks.append(kind)
        if kind == b'sTER':
            assert mode is None and length == 1
            mode = body[0]
        pos += length + 12
    assert pos == len(data) and chunks[0] == b'IHDR' and chunks[-1] == b'IEND'
    assert mode == 1 and chunks.index(b'sTER') < chunks.index(b'IDAT'), path
    image = np.asarray(Image.open(path).convert('RGBA'))
    padding = 15 - ((image.shape[1] - 1) % 16)
    assert padding <= 7 and (image.shape[1] - padding) % 2 == 0
    width = (image.shape[1] - padding) // 2
    assert (width + padding) % 8 == 0
    return image[:, :width], image[:, width+padding:]


def shift(left, right):
    def canvas(image):
        premultiplied = image.astype(float) / 255
        premultiplied[..., :3] *= premultiplied[..., 3:4]
        return np.pad(premultiplied, ((8, 8), (8, 8), (0, 0)))
    assert left[..., 3].max() > 0 and right[..., 3].max() > 0, 'Empty group probe'
    a, b = canvas(left), canvas(right)
    candidates = []
    for dy in range(-2, 3):
        for dx in range(-5, 6):
            error = float(np.square(a - np.roll(b, (dy, dx), (0, 1))).sum())
            candidates.append((error, dx, dy))
    return min(candidates)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('folder', type=Path)
    p.add_argument('--negative', action='store_true')
    a = p.parse_args()
    if a.negative:
        left, right = pair(a.folder / 'negative-flat.pns')
        error, dx, dy = shift(left, right)
        print(json.dumps({'expected': [1, 0], 'measured': [dx, dy], 'squared_error': error}))
        assert (dx, dy) == (1, 0), 'Flat control correctly fails the popped-depth expectation'
        return
    verified = 0
    for path in a.folder.glob('*.pns'):
        pair(path)
        verified += 1
    rows = []
    for name, expected in [('g3010', -1), ('g3050', 0), ('g3090', 1)]:
        left, right = pair(a.folder / f'{name}-256.pns')
        error, dx, dy = shift(left, right)
        rows.append({'group': name, 'expected_disparity': expected, 'measured_disparity': dx,
                     'vertical_disparity': dy, 'squared_error': error})
        assert dx == expected and dy == 0 and error < 0.01, rows[-1]
    left, right = pair(a.folder / 'pair-256.pns')
    assert np.array_equal(left, np.array(Image.open(a.folder / 'left.png').convert('RGBA')))
    assert np.array_equal(right, np.array(Image.open(a.folder / 'right.png').convert('RGBA')))
    print(json.dumps({'marked_files_verified': verified, 'rows': rows, 'eye_round_trip': 'exact'}, indent=2))


if __name__ == '__main__':
    main()
