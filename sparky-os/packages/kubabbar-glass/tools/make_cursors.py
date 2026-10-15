#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Draw the Kubabbar Glass cursors (original shapes: a silver arrow, a text beam, a turning ring) and write them as an Xcursor theme."""
import math
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "share/icons/kubabbar-glass-cursors"
SIZES = (24, 32, 48, 64)
SS = 4
INK, LIGHT, SILVER, DARK = (36, 43, 33, 255), (252, 253, 249, 255), (203, 208, 197, 255), (132, 140, 124, 255)


def canvas(size):
    return Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))


def gradient(box, top, bottom):
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", (x1 - x0, y1 - y0))
    px = layer.load()
    for y in range(layer.height):
        t = y / max(1, layer.height - 1)
        for x in range(layer.width):
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return layer


def finish(image, size, shadow):
    if shadow:
        mask = image.getchannel("A").filter(ImageFilter.GaussianBlur(1.2 * SS))
        shade = Image.new("RGBA", image.size, (0, 0, 0, 0))
        shade.putalpha(mask.point(lambda v: v * 0.38))
        shifted = ImageChops.offset(shade, SS, SS)
        shifted.alpha_composite(image)
        image = shifted
    return image.resize((size, size), Image.LANCZOS)


def arrow(size):
    s = size * SS / 24
    points = [(3, 2), (3, 19), (7.4, 14.9), (10.4, 21.6), (13.2, 20.4), (10.2, 13.9), (16, 13.9)]
    poly = [(x * s, y * s) for x, y in points]
    image = canvas(size)
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    fill = gradient((0, 0, image.width, image.height), LIGHT, DARK)
    body = Image.new("RGBA", image.size, (0, 0, 0, 0))
    body.paste(fill, (0, 0), mask)
    image.alpha_composite(body)
    draw = ImageDraw.Draw(image)
    draw.line(poly + [poly[0]], fill=INK, width=max(1, round(1.4 * s)), joint="curve")
    inner = [(3.9 * s, 4.6 * s), (3.9 * s, 15.4 * s)]
    draw.line(inner, fill=(255, 255, 255, 230), width=max(1, round(0.9 * s)))
    return finish(image, size, True), (round(3 * size / 24), round(2 * size / 24))


def beam(size):
    s = size * SS / 24
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    for color, width in ((INK, 4.2), (LIGHT, 2.0)):
        w = round(width * s / 2)
        draw.line([(12 * s, 4.5 * s), (12 * s, 19.5 * s)], fill=color, width=round(width * s / 1.5) if color == LIGHT else round(width * s))
        for y in (4.5, 19.5):
            draw.line([(8.6 * s, y * s), (15.4 * s, y * s)], fill=color, width=round(width * s / 1.5) if color == LIGHT else round(width * s))
    return finish(image, size, True), (size // 2, size // 2)


def ring(size, step, steps=12):
    s = size * SS / 24
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    cx = cy = 12 * s
    for i in range(steps):
        angle = 2 * math.pi * i / steps
        age = (i - step) % steps
        tone = round(70 + 185 * (1 - age / steps))
        x, y = cx + math.cos(angle) * 7.4 * s, cy + math.sin(angle) * 7.4 * s
        r = (1.7 if age == 0 else 1.35) * s
        draw.ellipse((x - r - 0.5 * s, y - r - 0.5 * s, x + r + 0.5 * s, y + r + 0.5 * s), fill=INK)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(tone, tone + 4, tone - 4, 255))
    return finish(image, size, True), (size // 2, size // 2)


def crosshair(size):
    s = size * SS / 24
    image = canvas(size)
    draw = ImageDraw.Draw(image)
    for color, width in ((INK, 3.6), (LIGHT, 1.6)):
        draw.line([(12 * s, 3 * s), (12 * s, 21 * s)], fill=color, width=round(width * s))
        draw.line([(3 * s, 12 * s), (21 * s, 12 * s)], fill=color, width=round(width * s))
    return finish(image, size, True), (size // 2, size // 2)


def pack(frames):
    """frames: list of (size, image, (xhot, yhot), delay_ms) -> Xcursor bytes (premultiplied ARGB)."""
    chunks = []
    for size, image, (xhot, yhot), delay in frames:
        px = image.convert("RGBA")
        data = bytearray()
        for r, g, b, a in px.get_flattened_data():
            data += struct.pack("<I", (a << 24) | (round(r * a / 255) << 16) | (round(g * a / 255) << 8) | round(b * a / 255))
        header = struct.pack("<IIIIIIIII", 36, 0xFFFD0002, size, 1, px.width, px.height, xhot, yhot, delay)
        chunks.append((size, header + bytes(data)))
    toc_start = 16
    position = toc_start + 12 * len(chunks)
    toc, body = b"", b""
    for size, chunk in chunks:
        toc += struct.pack("<III", 0xFFFD0002, size, position + len(body))
        body += chunk
    return b"Xcur" + struct.pack("<III", 16, 0x10000, len(chunks)) + toc + body


def main():
    cursors = OUT / "cursors"
    cursors.mkdir(parents=True, exist_ok=True)
    still = {"left_ptr": arrow, "text": beam, "cross": crosshair}
    for name, draw in still.items():
        frames = [(size, *draw(size), 0) for size in SIZES]
        (cursors / name).write_bytes(pack(frames))
    frames = [(size, *ring(size, step), 90) for step in range(12) for size in SIZES]
    (cursors / "wait").write_bytes(pack(frames))
    aliases = {"default": "left_ptr", "arrow": "left_ptr", "top_left_arrow": "left_ptr", "ibeam": "text", "xterm": "text",
               "crosshair": "cross", "watch": "wait", "progress": "wait"}
    for alias, target in aliases.items():
        link = cursors / alias
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(target)
    (OUT / "index.theme").write_text(
        "[Icon Theme]\nName=Kubabbar Glass cursors\nComment=Silver arrow, text beam and turning ring, drawn for Kubabbar Glass; other cursors come from Oxygen White\n"
        "Inherits=Oxygen_White\n")
    print("cursors written to", OUT)


if __name__ == "__main__":
    main()
