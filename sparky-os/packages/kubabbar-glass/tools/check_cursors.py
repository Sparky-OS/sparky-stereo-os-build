#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Read the cursors back with libXcursor and draw a preview sheet."""
import ctypes
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CURSORS = ROOT / "share/icons/kubabbar-glass-cursors/cursors"
lib = ctypes.CDLL("libXcursor.so.1")


class XcursorImage(ctypes.Structure):
    _fields_ = [("version", ctypes.c_uint32), ("size", ctypes.c_uint32), ("width", ctypes.c_uint32), ("height", ctypes.c_uint32),
                ("xhot", ctypes.c_uint32), ("yhot", ctypes.c_uint32), ("delay", ctypes.c_uint32), ("pixels", ctypes.POINTER(ctypes.c_uint32))]


class XcursorImages(ctypes.Structure):
    _fields_ = [("nimage", ctypes.c_int), ("images", ctypes.POINTER(ctypes.POINTER(XcursorImage))), ("name", ctypes.c_char_p)]


lib.XcursorFilenameLoadImages.restype = ctypes.POINTER(XcursorImages)
lib.XcursorFilenameLoadImages.argtypes = [ctypes.c_char_p, ctypes.c_int]


def load(name, size):
    images = lib.XcursorFilenameLoadImages(str(CURSORS / name).encode(), size)
    if not images:
        sys.exit(f"{name}: libXcursor cannot read it")
    out = []
    for i in range(images.contents.nimage):
        image = images.contents.images[i].contents
        raw = ctypes.string_at(image.pixels, image.width * image.height * 4)
        picture = Image.frombytes("RGBA", (image.width, image.height), raw, "raw", "BGRA")
        out.append((picture, image.xhot, image.yhot, image.delay, image.width))
    return out


def main():
    report = {}
    sheet = Image.new("RGBA", (4 * 140, 2 * 140), (0, 0, 0, 0))
    backgrounds = ((216, 217, 213, 255), (40, 44, 38, 255))
    for row, bg in enumerate(backgrounds):
        panel = Image.new("RGBA", (4 * 140, 140), bg)
        sheet.paste(panel, (0, row * 140))
    for column, name in enumerate(("left_ptr", "text", "cross", "wait")):
        for size in (24, 32, 48, 64):
            images = load(name, size)
            assert images, name
            picture, xhot, yhot, delay, width = images[0]
            assert width == size and 0 <= xhot < size and 0 <= yhot < size, (name, size, width, xhot, yhot)
            report[f"{name}@{size}"] = {"frames": len(images), "hotspot": [xhot, yhot], "delay": delay}
            alpha = picture.getchannel("A")
            assert alpha.getbbox() and alpha.getextrema()[1] > 200, f"{name}@{size} is empty"
        picture, *_ = load(name, 48)[0 if name != "wait" else 3]
        for row in (0, 1):
            sheet.alpha_composite(picture, (column * 140 + 46, row * 140 + 46))
    sheet.save(ROOT / "evidence/m2/cursors-preview.png")
    for name in ("default", "arrow", "ibeam", "xterm", "watch", "progress", "crosshair"):
        assert load(name, 32), name
    for key, value in report.items():
        print(key, value)
    print("all cursors read back by libXcursor")


if __name__ == "__main__":
    main()
