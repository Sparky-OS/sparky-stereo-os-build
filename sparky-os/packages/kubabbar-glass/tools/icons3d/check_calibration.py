#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""End-to-end check of the stereo rig on the rendered images: two emissive crosses, one on the convergence plane and one nearer.

    check_calibration.py RENDER_DIR SIZE EVIDENCE_JSON

Finds each cross in both eyes by the centroid of its bright pixels and compares the measured disparity with the projection of the
recipe's cameras. A cross on the plane must measure zero, a nearer one crossed disparity, both within 0.15 px.
"""
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_icons import project, read_png16


def centroids(image):
    rgba = image.astype(np.float64) / 65535.0
    bright = (rgba[..., 3] > 0.9) & (rgba[..., :3].min(axis=-1) > 0.9)
    ys, xs = np.nonzero(bright)
    middle = image.shape[1] / 2
    out = {}
    for name, mask in (("near", xs < middle), ("plane", xs >= middle)):
        weights = rgba[ys[mask], xs[mask], :3].mean(axis=-1)
        out[name] = (float((xs[mask] * weights).sum() / weights.sum()) + 0.5, int(mask.sum()))
    return out


def main(render_dir, size, evidence):
    render_dir, size = Path(render_dir), int(size)
    recipe = json.loads((render_dir / "calibration.recipe.json").read_text())
    left = centroids(read_png16(render_dir / ("calibration-%d-left.png" % size)))
    right = centroids(read_png16(render_dir / ("calibration-%d-right.png" % size)))
    centre = np.array((0.0, 0.0, 0.62))
    forward = centre - np.array(recipe["cameras"]["centre"]["location"])
    forward /= np.linalg.norm(forward)
    rv = np.array(recipe["cameras"]["right"]["location"]) - np.array(recipe["cameras"]["left"]["location"])
    rv /= np.linalg.norm(rv)
    points = {"plane": centre + rv * 0.35, "near": centre - rv * 0.35 - forward * 0.4}
    result, ok = {}, True
    for name, point in points.items():
        expected = (project(recipe, "right", point)[0] - project(recipe, "left", point)[0]) * size
        measured = right[name][0] - left[name][0]
        good = abs(measured - expected) < 0.15
        ok &= good
        result[name] = {"measured_px": round(measured, 3), "expected_px": round(expected, 3), "pass": bool(good), "bright_pixels": [left[name][1], right[name][1]]}
    result["size_px"] = size
    result["all_pass"] = bool(ok)
    Path(evidence).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(*sys.argv[1:4])
