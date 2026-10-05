"""Generate and numerically verify the stereo outputs."""

from pathlib import Path
import json
import subprocess
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from mpl_toolkits.mplot3d import proj3d

from mpl_parallel_stereo import save_stereo_figure, save_stereo_frames, save_stereo_video

MARKER_COLOURS = {
    "centre": (255, 0, 255),
    "near": (0, 255, 0),
    "far": (0, 0, 255),
}


def depth_points(axis, distance=0.3):
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

    centre = data_point(world_centre[:3])
    near = data_point(world_centre[:3] + distance * forward)
    far = data_point(world_centre[:3] - distance * forward)
    return centre, near, far


def create_figure(marker_size=4):
    figure = plt.figure(figsize=(6, 4), dpi=50)
    axis_3d = figure.add_axes((0.28, 0.12, 0.66, 0.72), projection="3d")
    axis_3d.set_title("3D title", pad=10)
    axis_3d.set_xlabel("X")
    axis_3d.set_ylabel("Y")
    axis_3d.set_zlabel("Z")
    axis_3d.set_box_aspect((1, 1, 1))
    centre, near, far = depth_points(axis_3d)
    points = np.array([centre, near, far])
    colours = [MARKER_COLOURS[name] for name in ("centre", "near", "far")]
    scatter = axis_3d.scatter(
        points[:, 0], points[:, 1], points[:, 2], c=np.array(colours) / 255.0,
        s=marker_size, marker="s", edgecolors="none", linewidths=0, depthshade=False,
    )

    axis_2d = figure.add_axes((0.02, 0.12, 0.20, 0.58))
    axis_2d.set_title("2D")
    axis_2d.plot([0, 1], [0, 1], color="black")
    axis_2d.set_xticks([])
    axis_2d.set_yticks([])
    figure.suptitle("Figure title")
    return figure, axis_3d, axis_2d, scatter


def marker_centroid(image, colour):
    matches = np.all(image == np.array(colour, dtype=image.dtype), axis=-1)
    if not matches.any():
        raise RuntimeError(f"marker colour {colour} not found")
    y_pixels, x_pixels = np.nonzero(matches)
    return np.array([x_pixels.mean(), y_pixels.mean()])


def measure_eye_pair(figure, eye_separation=65.0, screen_distance=350.0):
    from mpl_parallel_stereo import _eye_array

    left = _eye_array(figure, "left", eye_separation, screen_distance)
    right = _eye_array(figure, "right", eye_separation, screen_distance)
    return left, right


def two_d_region(axis_2d, image_shape):
    figure = axis_2d.figure
    figure.canvas.draw()
    extent = axis_2d.get_window_extent()
    x0 = int(np.floor(extent.x0))
    y0 = int(np.floor(extent.y0))
    x1 = int(np.ceil(extent.x1))
    y1 = int(np.ceil(extent.y1))
    x0 = max(0, x0)
    y0 = max(0, y0)
    x1 = min(image_shape[1], x1)
    y1 = min(image_shape[0], y1)
    return slice(y0, y1), slice(x0, x1)


def verify_still(left, right, axis_2d):
    results = {}
    for name in ("centre", "near", "far"):
        left_point = marker_centroid(left, MARKER_COLOURS[name])
        right_point = marker_centroid(right, MARKER_COLOURS[name])
        disparity = left_point - right_point
        results[name] = {
            "left": left_point.tolist(),
            "right": right_point.tolist(),
            "disparity": disparity.tolist(),
        }

    y_slice, x_slice = two_d_region(axis_2d, left.shape)
    left_region = left[y_slice, x_slice]
    right_region = right[y_slice, x_slice]
    different_pixels = int(np.count_nonzero(np.any(left_region != right_region, axis=-1)))
    maximum_difference = int(np.max(np.abs(left_region.astype(int) - right_region.astype(int))))

    checks = {
        "centre_x_zero": results["centre"]["disparity"][0] == 0.0,
        "centre_y_zero": results["centre"]["disparity"][1] == 0.0,
        "near_x_positive": results["near"]["disparity"][0] > 0.0,
        "far_x_negative": results["far"]["disparity"][0] < 0.0,
        "vertical_zero": all(
            results[name]["disparity"][1] == 0.0
            for name in ("centre", "near", "far")
        ),
        "two_d_identical": different_pixels == 0,
    }
    return {
        "markers": results,
        "two_d": {
            "region_pixels": int(left_region.shape[0] * left_region.shape[1]),
            "different_pixels": different_pixels,
            "maximum_difference": maximum_difference,
        },
        "checks": checks,
    }


def update_animation(frame, axis_3d, scatter):
    axis_3d.view_init(elev=30, azim=-60 + 12 * frame)
    centre, near, far = depth_points(axis_3d)
    points = np.array([centre, near, far])
    scatter._offsets3d = (points[:, 0], points[:, 1], points[:, 2])


def create_animation(figure, axis_3d, scatter):
    return FuncAnimation(
        figure, update_animation, frames=4, fargs=(axis_3d, scatter),
        cache_frame_data=False,
    )


def probe_file(path):
    command = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,codec_name:side_data_list",
        "-of", "json", str(path),
    ]
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE, text=True)
    return json.loads(result.stdout)


def main():
    output = Path("build/test")
    output.mkdir(parents=True, exist_ok=True)

    figure, axis_3d, axis_2d, scatter = create_figure()
    left, right = measure_eye_pair(figure)
    verification = verify_still(left, right, axis_2d)

    still_png = output / "stereo.png"
    still_jpg = output / "stereo.jpg"
    save_stereo_figure(figure, still_png)
    save_stereo_figure(figure, still_jpg)

    animation = create_animation(figure, axis_3d, scatter)
    frame_paths = save_stereo_frames(animation, output / "frames")
    video_mkv = save_stereo_video(animation, output / "stereo.mkv", fps=4)
    video_mp4 = save_stereo_video(animation, output / "stereo.mp4", fps=4)

    probes = {
        "mkv": probe_file(video_mkv),
        "mp4": probe_file(video_mp4),
    }

    report = {
        "figure_size": [int(figure.get_size_inches()[0] * figure.dpi),
                         int(figure.get_size_inches()[1] * figure.dpi)],
        "stereo_size": [left.shape[1] * 2, left.shape[0]],
        "still": verification,
        "frame_count": len(frame_paths),
        "frames": [str(path) for path in frame_paths],
        "videos": {
            "mkv": str(video_mkv),
            "mp4": str(video_mp4),
        },
        "ffprobe": probes,
    }

    evidence = Path("evidence/stereo-proof.json")
    evidence.parent.mkdir(exist_ok=True)
    evidence.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    if not all(verification["checks"].values()):
        raise SystemExit("stereo verification failed")

    print(json.dumps({
        "figure_size": report["figure_size"],
        "stereo_size": report["stereo_size"],
        "frame_count": report["frame_count"],
        "checks": verification["checks"],
        "markers": verification["markers"],
        "two_d": verification["two_d"],
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
