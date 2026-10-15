# SPDX-License-Identifier: GPL-3.0-only
"""Render one icon as a stereo pair at every size, 16 bit per channel.

    blender -b --python render_blender.py -- ICON OUTDIR [SIZE ...]

For each size and eye the model is rendered at four times the size (Cycles, linear OpenEXR), reduced by a box filter in linear light on
premultiplied colour, encoded as sRGB and written as a 16-bit RGBA PNG without dithering. Alongside go the recipe (JSON) with the
camera numbers and the checks' inputs.
"""
import json
import math
import os
import struct
import sys
import zlib
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import models
import scene as studio

SUPERSAMPLE = 4
FRAME_CENTRE, FRAME_RADIUS = (0.0, 0.0, 0.62), 1.0
DEFAULT_SIZES = (16, 22, 32, 48, 64, 128, 256)


def write_png16(path, rgba):
    """Straight-alpha RGBA, uint16 array (h, w, 4) -> PNG, filter type 0 on every row."""
    height, width, _ = rgba.shape
    raw = b"".join(b"\x00" + rgba[y].astype(">u2").tobytes() for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 16, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def srgb_encode(linear):
    linear = np.clip(linear, 0.0, 1.0)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * np.power(linear, 1 / 2.4) - 0.055)


def load_exr(path):
    image = bpy.data.images.load(str(path))
    image.colorspace_settings.name = "Non-Color"
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return np.flipud(pixels.reshape(height, width, 4))


def reduce(premult, factor):
    height, width, _ = premult.shape
    return premult.reshape(height // factor, factor, width // factor, factor, 4).mean(axis=(1, 3))


def to_png16(premult):
    alpha = premult[..., 3:4]
    colour = np.where(alpha > 1e-6, premult[..., :3] / np.maximum(alpha, 1e-6), 0.0)
    encoded = srgb_encode(colour)
    out = np.concatenate([encoded, np.clip(alpha, 0, 1)], axis=-1)
    return np.round(out * 65535).astype(np.uint16)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    icon, out = argv[0], Path(argv[1])
    sizes = [int(s) for s in argv[2:]] or list(DEFAULT_SIZES)
    out.mkdir(parents=True, exist_ok=True)
    studio.reset()
    if icon != "calibration":
        models.MODELS[icon]()
    studio.studio()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "floor"]
    low = Vector((1e9,) * 3)
    high = Vector((-1e9,) * 3)
    for world in studio.evaluated_corners(meshes):
        low = Vector((min(low[i], world[i]) for i in range(3)))
        high = Vector((max(high[i], world[i]) for i in range(3)))
    # One framing and one depth scale for the whole set, so a family of icons keeps its size and its depth from icon to icon.
    centre, radius = Vector(FRAME_CENTRE), FRAME_RADIUS
    studio.DISTANCE = 1.12 * radius / math.tan(studio.HFOV / 2) * 0.98
    cameras, right, plane_width, position, forward = studio.rig(centre)
    if icon == "calibration":
        models.calibration(centre, right, forward, cameras["centre"].rotation_euler)
        meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name != "floor"]
    near, far = studio.DISTANCE - radius, studio.DISTANCE + radius
    model_near, model_far = studio.depth_range(position, forward, meshes)
    base = studio.separation(near, far)
    studio.place_eyes(cameras, right, plane_width, base)
    studio.render_settings(int(os.environ.get("ICON_SAMPLES", "96")))
    recipe = {"icon": icon, "azimuth_deg": math.degrees(studio.AZIMUTH), "elevation_deg": math.degrees(studio.ELEVATION),
              "distance": studio.DISTANCE, "hfov_deg": math.degrees(studio.HFOV), "separation": base,
              "convergence_plane_distance": studio.DISTANCE, "depth_range_fraction_of_width": studio.DEPTH_RANGE,
              "frame_depth_near": near, "frame_depth_far": far, "model_depth_near": model_near, "model_depth_far": model_far, "supersample": SUPERSAMPLE,
              "cameras": {eye: {"location": list(cameras[eye].location), "rotation_euler": list(cameras[eye].rotation_euler),
                                "shift_x": cameras[eye].data.shift_x} for eye in cameras},
              "sizes": sizes, "bbox": [list(low), list(high)]}
    (out / (icon + ".recipe.json")).write_text(json.dumps(recipe, indent=2) + "\n")
    tmp = out / "tmp"
    tmp.mkdir(exist_ok=True)
    for size in sizes:
        bpy.context.scene.render.resolution_x = bpy.context.scene.render.resolution_y = size * SUPERSAMPLE
        for eye in ("left", "right"):
            bpy.context.scene.camera = cameras[eye]
            exr = tmp / ("%s-%d-%s.exr" % (icon, size, eye))
            bpy.context.scene.render.filepath = str(exr)
            bpy.ops.render.render(write_still=True)
            picture = to_png16(reduce(load_exr(exr), SUPERSAMPLE))
            write_png16(out / ("%s-%d-%s.png" % (icon, size, eye)), picture)
            exr.unlink()
            print("rendered", icon, size, eye, flush=True)
    tmp.rmdir()


main()
