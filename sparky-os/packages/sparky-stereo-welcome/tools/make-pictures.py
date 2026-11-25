#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# make-pictures.py SLIDES_DIR OUT_DIR: the Welcome's stereo pictures, cut from the installer's slides of the SparkyOS
# artwork (sparky-stereo-calamares-branding): the same rectangle of each eye, copied, nothing resized, so the depth the
# artwork was drawn with stays as it is. The installer's progress dots and the wordmark stay out of the cut.
# Each picture is written as a full side by side PNG, left eye first, with PNG's sTER chunk (mode 1, PNG Extensions
# 1.4.0, 3.6) right after IHDR, and read back before it is kept. Needs python3-pil.
import io
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

EYE_WIDTH = 1280
EYE_HEIGHT = 720
# name in the Welcome, the slide, and the rectangle of one eye (left, top, right, bottom), the same in both eyes
PICTURES = [
    ("any-screen", "slide11-any-screen.pns", (704, 152, 1216, 552)),
]


def chunks(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length:pos + 12 + length])[0]
        if zlib.crc32(kind + body) & 0xFFFFFFFF != crc:
            raise ValueError("bad CRC in %r" % kind)
        yield kind, body
        pos += 12 + length


def with_ster(png):
    out = png[:8]
    for kind, body in chunks(png):
        out += struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        if kind == b"IHDR":
            ster = b"\x01"
            out += struct.pack(">I", 1) + b"sTER" + ster + struct.pack(">I", zlib.crc32(b"sTER" + ster) & 0xFFFFFFFF)
    return out


def main():
    slides, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for name, slide, (left, top, right, bottom) in PICTURES:
        pair = Image.open(slides / slide).convert("RGB")
        if pair.size != (2 * EYE_WIDTH, EYE_HEIGHT):
            raise SystemExit("%s: %dx%d, a pair of %dx%d eyes was expected" % (slide, *pair.size, EYE_WIDTH, EYE_HEIGHT))
        width = right - left
        if width % 8:
            raise SystemExit("%s: the eye width %d is not a multiple of 8 (sTER padding)" % (name, width))
        result = Image.new("RGB", (2 * width, bottom - top))
        result.paste(pair.crop((left, top, right, bottom)), (0, 0))
        result.paste(pair.crop((EYE_WIDTH + left, top, EYE_WIDTH + right, bottom)), (width, 0))
        buffer = io.BytesIO()
        result.save(buffer, "PNG", optimize=True)
        data = with_ster(buffer.getvalue())
        kinds = [kind for kind, _ in chunks(data)]
        if kinds[:2] != [b"IHDR", b"sTER"] or kinds.count(b"sTER") != 1:
            raise SystemExit("%s: the sTER chunk is not right after IHDR: %r" % (name, kinds[:3]))
        back = Image.open(io.BytesIO(data)).convert("RGB")
        if back.tobytes() != result.tobytes():
            raise SystemExit("%s: the written picture does not read back the same" % name)
        (out / (name + ".pns")).write_bytes(data)
        print("%s.pns %dx%d, eyes %dx%d from %s, sTER 1" % (name, result.width, result.height, width, bottom - top, slide))


if __name__ == "__main__":
    main()
