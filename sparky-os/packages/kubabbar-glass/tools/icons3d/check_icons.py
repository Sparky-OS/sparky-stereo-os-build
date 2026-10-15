#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Checks for the 3D icon pipeline: the stereo rig, the 16-bit depth of the renders, and the readability of empty against full.

    check_icons.py RENDER_DIR EVIDENCE_JSON

RENDER_DIR holds NAME-SIZE-left.png / -right.png (16 bit, written by render_blender.py) and NAME.recipe.json.
"""
import json
import math
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

SIZES = (16, 22, 32, 48, 64, 128, 256)
ICONS = ("user-trash", "user-trash-full")


def read_png16(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    position, idat, header = 8, b"", None
    while position < len(data):
        length, kind = struct.unpack(">I4s", data[position:position + 8])
        body = data[position + 8:position + 8 + length]
        position += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
    width, height, depth, colour = header[:4]
    assert (depth, colour) == (16, 6), f"{path}: expected 16-bit RGBA, got depth {depth} colour type {colour}"
    raw = zlib.decompress(idat)
    stride = width * 8 + 1
    rows = np.frombuffer(raw, dtype=np.uint8).reshape(height, stride)
    assert (rows[:, 0] == 0).all(), "only filter 0 expected from our writer"
    return rows[:, 1:].copy().view(">u2").reshape(height, width, 4).astype(np.uint16)


def project(recipe, eye, point):
    """Pinhole projection with the camera's shift: horizontal position as a fraction of the picture width."""
    camera = recipe["cameras"][eye]
    rx, ry, rz = camera["rotation_euler"]
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    rotation = np.array([[cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx],
                         [sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx],
                         [-sy, cy * sx, cy * cx]])
    local = rotation.T @ (np.array(point) - np.array(camera["location"]))
    half = math.tan(math.radians(recipe["hfov_deg"]) / 2)
    return (local[0] / -local[2]) / (2 * half) + 0.5 - camera["shift_x"], local[2]  # Blender: a positive shift moves the content left


def rig_check(recipe):
    out = {}
    left, right = recipe["cameras"]["left"], recipe["cameras"]["right"]
    out["axes_parallel"] = left["rotation_euler"] == right["rotation_euler"] == recipe["cameras"]["centre"]["rotation_euler"]
    centre = np.array(recipe["bbox"][0]) * 0 + np.array((0.0, 0.0, 0.62))
    forward = centre - np.array(recipe["cameras"]["centre"]["location"])
    forward /= np.linalg.norm(forward)
    right_vector = np.array(recipe["cameras"]["right"]["location"]) - np.array(recipe["cameras"]["left"]["location"])
    right_vector /= np.linalg.norm(right_vector)
    results = {}
    for name, lateral, depth in (("convergence plane, centre", 0.0, 0.0), ("convergence plane, off axis", 0.3, 0.0), ("0.4 nearer", 0.0, -0.4), ("0.4 farther", 0.0, 0.4)):
        point = centre + right_vector * lateral + forward * depth
        ul, _ = project(recipe, "left", point)
        ur, _ = project(recipe, "right", point)
        results[name] = (ur - ul) * 1.0
    out["disparity_right_minus_left_fraction_of_width"] = results
    out["zero_on_plane"] = abs(results["convergence plane, centre"]) < 1e-6 and abs(results["convergence plane, off axis"]) < 1e-6
    out["crossed_when_nearer"] = results["0.4 nearer"] < 0 < results["0.4 farther"]
    out["frame_depth_range_fraction"] = results["0.4 farther"] - results["0.4 nearer"]
    return out


def flat_fraction(channel, bits, low, high):
    """Fraction of gently ramping pixels that sit in a flat run of at least three equal values once the picture is held at BITS per channel."""
    quant = (channel.astype(np.int64) >> (16 - bits))
    gradient = np.abs(np.diff(channel.astype(np.int64), axis=1))
    ramp = (gradient >= low) & (gradient <= high)
    flat_pairs = np.diff(quant, axis=1) == 0
    runs = flat_pairs[:, :-1] & flat_pairs[:, 1:]
    mask = ramp[:, :-1] & ramp[:, 1:]
    return float((runs & mask).sum() / max(1, mask.sum())), int(mask.sum())


def banding(image):
    rgba = image.astype(np.int64)
    alpha = rgba[..., 3]
    opaque = alpha >= 65000
    luminance = (0.2126 * rgba[..., 0] + 0.7152 * rgba[..., 1] + 0.0722 * rgba[..., 2]).astype(np.int64)
    luminance = np.where(opaque, luminance, -1)
    out = {}
    for bits in (8, 10, 12, 16):
        fraction, count = flat_fraction(luminance, bits, 4, 400)
        out["luminance_flat_run_fraction_at_%d_bit" % bits] = round(fraction, 4)
    out["ramp_pixels"] = count
    shadow = (alpha > 400) & (alpha < 40000)
    out["distinct_alpha_levels_in_shadow"] = int(len(np.unique(alpha[shadow])))
    out["distinct_luminance_levels_on_metal"] = int(len(np.unique(luminance[luminance >= 0])))
    out["distinct_8bit_luminance_levels_on_metal"] = int(len(np.unique(luminance[luminance >= 0] >> 8)))
    return out


def over_grey(image, grey=0.5):
    rgba = image.astype(np.float64) / 65535.0
    return rgba[..., :3] * rgba[..., 3:4] + grey * (1 - rgba[..., 3:4])


def main(render_dir, evidence):
    render_dir = Path(render_dir)
    result = {"icons": {}}
    ok = True
    for icon in ICONS:
        recipe = json.loads((render_dir / (icon + ".recipe.json")).read_text())
        rig = rig_check(recipe)
        ok &= rig["axes_parallel"] and rig["zero_on_plane"] and rig["crossed_when_nearer"]
        big = read_png16(render_dir / ("%s-256-left.png" % icon))
        bands = banding(big)
        ok &= bands["luminance_flat_run_fraction_at_16_bit"] < 0.02 and bands["distinct_luminance_levels_on_metal"] > 4 * bands["distinct_8bit_luminance_levels_on_metal"]
        result["icons"][icon] = {"rig": rig, "banding_256_left": bands}
    result["states_differ"] = {}
    for size in SIZES:
        empty = over_grey(read_png16(render_dir / ("user-trash-%d-left.png" % size)))
        full = over_grey(read_png16(render_dir / ("user-trash-full-%d-left.png" % size)))
        difference = float(np.abs(empty - full).mean())
        result["states_differ"][str(size)] = round(difference, 4)
        ok &= difference > 0.004
    result["all_pass"] = bool(ok)
    Path(evidence).write_text(json.dumps(result, indent=2, default=lambda o: bool(o) if isinstance(o, np.bool_) else float(o)) + "\n")
    print(json.dumps(result, indent=2, default=lambda o: bool(o) if isinstance(o, np.bool_) else float(o)))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(*sys.argv[1:3])
