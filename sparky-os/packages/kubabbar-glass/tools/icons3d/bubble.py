#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""The glass bubble overlay: original artwork with alpha, and its per-eye depth profile.

    bubble.py OUT_DIR SIZE_PX CENTRE_POP_PX ICON.png [ICON.png ...]

The bubble is a sphere seen from the front: its rim lies in the icon's own plane (zero disparity) and its centre is popped by
CENTRE_POP_PX (0.5 px by default, up to 2 px, the same for every icon). The disparity at radius r is the sphere's height,
    d(r) = CENTRE_POP_PX * sqrt(1 - (r / R)^2),
so each eye sees every point of the overlay shifted by +d(r)/2 (left eye) or -d(r)/2 (right eye). The icon underneath is
flat, at the plane, identical in both eyes.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<!-- SPDX-License-Identifier: GPL-3.0-only. Original artwork of Kubabbar Glass: a clear glass bubble with alpha, for laying over any icon. -->
<defs>
<radialGradient id="body" cx=".5" cy=".5" r=".5">
<stop offset="0" stop-color="#ffffff" stop-opacity=".02"/><stop offset=".72" stop-color="#e8f1f6" stop-opacity=".07"/>
<stop offset=".9" stop-color="#d4e4ec" stop-opacity=".30"/><stop offset=".97" stop-color="#ffffff" stop-opacity=".55"/><stop offset="1" stop-color="#ffffff" stop-opacity=".12"/>
</radialGradient>
<radialGradient id="glint" cx=".5" cy=".5" r=".5">
<stop offset="0" stop-color="#ffffff" stop-opacity=".95"/><stop offset=".55" stop-color="#ffffff" stop-opacity=".5"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
</radialGradient>
<linearGradient id="floor" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#3a5666" stop-opacity="0"/><stop offset="1" stop-color="#2d4654" stop-opacity=".26"/>
</linearGradient>
<linearGradient id="bounce" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#9fe3ff" stop-opacity="0"/><stop offset="1" stop-color="#bff0ff" stop-opacity=".45"/>
</linearGradient>
</defs>
<circle cx="128" cy="128" r="120" fill="url(#body)"/>
<circle cx="128" cy="128" r="119" fill="url(#floor)"/>
<circle cx="128" cy="128" r="119.5" fill="none" stroke="#1f3340" stroke-opacity=".28" stroke-width="2"/>
<path d="M60 160 A74 74 0 0 0 196 184 A92 92 0 0 1 60 160 Z" fill="url(#bounce)"/>
<g transform="rotate(-38 92 78)"><ellipse cx="92" cy="78" rx="58" ry="24" fill="url(#glint)"/></g>
<ellipse cx="176" cy="188" rx="13" ry="6" fill="#ffffff" fill-opacity=".45" transform="rotate(-38 176 188)"/>
</svg>
"""


def rasterise(svg_path, size):
    png = svg_path.with_suffix(".%d.png" % size)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(png)], check=True)
    image = np.asarray(Image.open(png).convert("RGBA"), dtype=np.float64) / 255.0
    png.unlink()
    return image


def warp(image, pop, sign):
    """Backward warp by the sphere profile: output(x, y) = image(x - sign * d(r) / 2, y). sign = +1 for the left eye."""
    size = image.shape[0]
    radius = size / 2 * 120 / 128
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    r = np.hypot(xs + 0.5 - size / 2, ys + 0.5 - size / 2)
    d = pop * np.sqrt(np.clip(1 - (r / radius) ** 2, 0, 1))
    source = xs - sign * d / 2
    x0 = np.clip(np.floor(source).astype(int), 0, size - 2)
    t = (source - x0)[..., None]
    rows = ys.astype(int)
    premult = image.copy()
    premult[..., :3] *= premult[..., 3:4]
    out = premult[rows, x0] * (1 - t) + premult[rows, x0 + 1] * t
    colour = np.where(out[..., 3:4] > 1e-6, out[..., :3] / np.maximum(out[..., 3:4], 1e-6), 0)
    return np.concatenate([colour, out[..., 3:4]], axis=-1)


def compose(icon, bubble):
    out = icon.copy()
    alpha = bubble[..., 3:4]
    out[..., :3] = bubble[..., :3] * alpha + icon[..., :3] * (1 - alpha)
    out[..., 3:4] = alpha + icon[..., 3:4] * (1 - alpha)
    return out


def measure(image_left, image_right, pop, size):
    """Block-match the highlight's brightest column band between the eyes, sub-pixel by parabola; returns right minus left."""
    radius = size / 2 * 120 / 128
    cx = size / 2 - 0.5
    patch = (slice(int(size * 0.22), int(size * 0.40)), slice(int(size * 0.25), int(size * 0.55)))
    a = image_left[..., 3][patch]
    best = None
    scores = []
    for shift in np.arange(-3.0, 3.01, 0.05):
        shifted = np.zeros_like(a)
        xs = np.arange(patch[1].start, patch[1].stop)
        for j, x in enumerate(xs):
            src = x + shift
            i0 = int(np.floor(src))
            t = src - i0
            shifted[:, j] = image_right[..., 3][patch[0], i0] * (1 - t) + image_right[..., 3][patch[0], i0 + 1] * t
        scores.append((float(np.abs(a - shifted).sum()), shift))
    best = min(scores)
    return best[1]


def main(out_dir, size, pop, *icons):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    size, pop = int(size), float(pop)
    svg = out / "glass-bubble.svg"
    svg.write_text(SVG)
    base = rasterise(svg, size)
    left, right = warp(base, pop, +1), warp(base, pop, -1)
    measured = measure(left, right, pop, size)
    row_l, row_r = [], []
    for icon in icons:
        picture = Image.open(icon).convert("RGBA").resize((size, size), Image.LANCZOS)
        flat = np.asarray(picture, dtype=np.float64) / 255.0
        row_l.append(compose(flat, left))
        row_r.append(compose(flat, right))
    if icons:
        eyes = [np.concatenate(r, axis=1) for r in (row_l, row_r)]
        sheet = np.concatenate(eyes, axis=1)
        background = np.array([196, 198, 192]) / 255.0
        rgb = sheet[..., :3] * sheet[..., 3:4] + background * (1 - sheet[..., 3:4])
        Image.fromarray(np.round(rgb * 255).astype(np.uint8)).save(out / ("bubble-sbs-%dpx-pop-%s.png" % (size, str(pop).replace(".", "_"))))
    (out / "glass-bubble.depth.json").write_text(json.dumps({
        "profile": "d(r) = pop * sqrt(1 - (r / R)^2), right-eye minus left-eye disparity is -d(r) (crossed: toward the viewer)",
        "rim_disparity_px": 0, "centre_pop_px_default": 0.5, "centre_pop_px_max": 2.0,
        "R_fraction_of_icon": 120 / 128, "same_for_every_icon": True,
        "measured_highlight_disparity_px": {"size": size, "pop": pop, "right_minus_left": round(measured, 2),
                                            "expected_at_highlight": round(-pop * float(np.sqrt(1 - ((np.hypot(0.31 * size - size / 2, 0.31 * size - size / 2)) / (size / 2 * 120 / 128)) ** 2)), 2)}}, indent=2) + "\n")
    print(json.dumps(json.loads((out / "glass-bubble.depth.json").read_text())["measured_highlight_disparity_px"]))


if __name__ == "__main__":
    main(*sys.argv[1:])
