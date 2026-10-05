"""Print numeric checks for the parallel off-axis Matplotlib camera."""

from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import proj3d

from mpl_parallel_stereo import _stereo_get_proj


def project(matrix, point):
    homogeneous = matrix @ np.append(np.asarray(point), 1.0)
    return homogeneous[:2] / homogeneous[3]


def main():
    fig = plt.figure(figsize=(6, 4), dpi=60)
    axis = fig.add_subplot(111, projection="3d")

    box_aspect = axis._roll_to_vertical(axis._box_aspect)
    world_m = proj3d.world_transformation(
        *axis.get_xlim3d(), *axis.get_ylim3d(), *axis.get_zlim3d(),
        pb_aspect=box_aspect,
    )
    limits = np.array([axis.get_xlim3d(), axis.get_ylim3d(), axis.get_zlim3d()])
    data_centre = limits.mean(axis=1)
    world_centre = world_m @ np.append(data_centre, 1.0)

    elevation = np.deg2rad(axis.elev)
    azimuth = np.deg2rad(axis.azim)
    direction = np.array([
        np.cos(elevation) * np.cos(azimuth),
        np.cos(elevation) * np.sin(azimuth),
        np.sin(elevation),
    ])
    direction = axis._roll_to_vertical(direction)
    _, _, forward = axis._calc_view_axes(world_centre[:3] + axis._dist * direction)

    inverse_world_m = np.linalg.inv(world_m)
    def data_point(world_point):
        return (inverse_world_m @ np.append(world_point, 1.0))[:3]
    near = data_point(world_centre[:3] + 0.25 * forward)
    far = data_point(world_centre[:3] - 0.25 * forward)
    centre = data_point(world_centre[:3])
    left = _stereo_get_proj(axis, -1.0, 65.0, 350.0)
    right = _stereo_get_proj(axis, 1.0, 65.0, 350.0)

    focal = axis._focal_length
    half_baseline = (axis._dist * focal * 65.0) / (2.0 * 350.0)
    print(f"focal_length={focal:.9g}")
    print(f"camera_distance={axis._dist:.9g}")
    print("eye,lateral_shift,principal_point_shift,persp_x02")
    for eye, lateral_shift in ((-1.0, -half_baseline), (1.0, half_baseline)):
        principal_shift = -focal * lateral_shift / axis._dist
        print(f"{eye:+.0f},{lateral_shift:+.9f},"
              f"{principal_shift:+.9f},{-principal_shift:+.9f}")

    print("point,left_x,left_y,right_x,right_y,disparity_x,disparity_y")
    for name, point in (("centre", centre), ("near", near), ("far", far)):
        left_xy = project(left, point)
        right_xy = project(right, point)
        disparity = left_xy - right_xy
        print(f"{name},{left_xy[0]:+.9f},{left_xy[1]:+.9f},"
              f"{right_xy[0]:+.9f},{right_xy[1]:+.9f},"
              f"{disparity[0]:+.9f},{disparity[1]:+.9f}")

    assert np.allclose(project(left, centre), project(right, centre), atol=1e-12)
    assert project(left, near)[0] - project(right, near)[0] > 0.0
    assert project(left, far)[0] - project(right, far)[0] < 0.0
    assert np.allclose(project(left, near)[1], project(right, near)[1], atol=1e-12)
    assert np.allclose(project(left, far)[1], project(right, far)[1], atol=1e-12)
    assert np.allclose(world_m @ np.append(centre, 1.0), world_centre)


if __name__ == "__main__":
    main()
