#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Lay the rendered icons out as the stereo icon theme kubabbar-glass-stereo, and write the review sheets.

    pack.py RENDER_DIR THEME_DIR PROOF_DIR

Layout (the edition's stereo icon rule: one picture, both views side by side, left eye first, twice as wide as the declared size):
    places/<size>/NAME.png            the left eye alone, 16 bit: what any 2D loader shows
    places/scalable/NAME.svg          the vector drawing
    stereo/places/<size>/NAME.png     left | right, 16 bit, under X-StereoDirectories (a loader that does not know the key ignores it)
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_icons import ICONS, SIZES, read_png16
import struct
import zlib


def write_png(path, array):
    """uint16 (h, w, 4) or uint8 (h, w, 3|4) -> PNG."""
    height, width, channels = array.shape
    depth = 16 if array.dtype == np.uint16 else 8
    colour = 6 if channels == 4 else 2
    raw = b"".join(b"\x00" + (array[y].astype(">u2") if depth == 16 else array[y]).tobytes() for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, depth, colour, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def to8(image):
    return np.round(image.astype(np.float64) / 257).astype(np.uint8)


def over(image, grey):
    rgba = image.astype(np.float64) / 65535.0
    out = rgba[..., :3] * rgba[..., 3:4] + (np.array(grey) / 255.0) * (1 - rgba[..., 3:4])
    return np.round(out * 255).astype(np.uint8)


def main(render_dir, theme_dir, proof_dir):
    render_dir, theme_dir, proof_dir = Path(render_dir), Path(theme_dir), Path(proof_dir)
    proof_dir.mkdir(parents=True, exist_ok=True)
    for icon in ICONS:
        for size in SIZES:
            left = read_png16(render_dir / ("%s-%d-left.png" % (icon, size)))
            right = read_png16(render_dir / ("%s-%d-right.png" % (icon, size)))
            flat = theme_dir / "places" / str(size)
            pair = theme_dir / "stereo/places" / str(size)
            flat.mkdir(parents=True, exist_ok=True)
            pair.mkdir(parents=True, exist_ok=True)
            write_png(flat / (icon + ".png"), left)
            write_png(pair / (icon + ".png"), np.concatenate([left, right], axis=1))
    for icon in ICONS:
        for size in (128, 256):
            left = read_png16(render_dir / ("%s-%d-left.png" % (icon, size)))
            right = read_png16(render_dir / ("%s-%d-right.png" % (icon, size)))
            write_png(proof_dir / ("%s-%d-sbs.png" % (icon, size)), np.concatenate([over(left, (196, 198, 192)), over(right, (196, 198, 192))], axis=1))
    print("packed", theme_dir)


main(*sys.argv[1:4])
