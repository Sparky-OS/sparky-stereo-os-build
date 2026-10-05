"""Parallel-camera side-by-side stereo export for Matplotlib figures.

Each view is rendered through a real camera.  The cameras are shifted half
the eye baseline along the view-right vector and use an off-axis perspective
projection so the axes centre stays on the screen plane.  The cameras remain
parallel; there is no toe-in rotation.
"""

from __future__ import annotations

import io
import subprocess
from pathlib import Path
from typing import Iterable

import numpy as np
from matplotlib.animation import FuncAnimation
from matplotlib.figure import Figure
from mpl_toolkits.mplot3d import proj3d
from mpl_toolkits.mplot3d.axes3d import Axes3D


_EYE_OFFSET = {"left": -1.0, "right": 1.0}


def _stereo_get_proj(axis: Axes3D, eye_offset: float, eye_separation: float,
                     screen_distance: float):
    """Build one parallel, off-axis projection for an Axes3D object."""
    if not np.isfinite(axis._focal_length):
        raise NotImplementedError(
            "Orthographic stereo is not supported because parallel "
            "orthographic rays discard depth, so two parallel cameras cannot "
            "produce parallax."
        )

    box_aspect = axis._roll_to_vertical(axis._box_aspect)
    world_m = proj3d.world_transformation(
        *axis.get_xlim3d(), *axis.get_ylim3d(), *axis.get_zlim3d(),
        pb_aspect=box_aspect,
    )
    centre = 0.5 * box_aspect

    elevation = np.deg2rad(axis.elev)
    azimuth = np.deg2rad(axis.azim)
    direction = np.array([
        np.cos(elevation) * np.cos(azimuth),
        np.cos(elevation) * np.sin(azimuth),
        np.sin(elevation),
    ])
    direction = axis._roll_to_vertical(direction)
    right, up, forward = axis._calc_view_axes(centre + axis._dist * direction)

    focal = axis._focal_length
    eye = centre + axis._dist * direction * focal
    half_baseline = (axis._dist * focal * eye_separation) / (2.0 * screen_distance)
    lateral_shift = eye_offset * half_baseline
    eye = eye + lateral_shift * right

    view_m = proj3d._view_transformation_uvw(right, up, forward, eye)
    persp_m = proj3d._persp_transformation(-axis._dist, axis._dist, focal)
    # The principal-point shift cancels the lateral camera position at the
    # screen plane while retaining depth-dependent parallax.
    persp_m[0, 2] = -focal * lateral_shift / axis._dist
    return np.dot(persp_m, np.dot(view_m, world_m))


class _StereoCameras:
    def __init__(self, fig: Figure, eye_separation: float, screen_distance: float):
        self.figure = fig
        self.eye_separation = eye_separation
        self.screen_distance = screen_distance
        self.axes = [axis for axis in fig.axes if isinstance(axis, Axes3D)]
        self._original_methods: dict[int, object] = {}

    def __enter__(self):
        for axis in self.axes:
            self._original_methods[id(axis)] = axis.get_proj
        return self

    def set_eye(self, eye: str):
        try:
            eye_offset = _EYE_OFFSET[eye]
        except KeyError as exc:
            raise ValueError("eye must be 'left' or 'right'") from exc
        for axis in self.axes:
            def get_proj(axis=axis, eye_offset=eye_offset):
                return _stereo_get_proj(
                    axis, eye_offset, self.eye_separation, self.screen_distance
                )
            axis.get_proj = get_proj
            axis.stale = True

    def __exit__(self, exc_type, exc, traceback):
        for axis in self.axes:
            original = self._original_methods.get(id(axis))
            if original is not None:
                axis.get_proj = original
                axis.stale = True
        return False


def _eye_array(fig: Figure, eye: str, eye_separation: float,
              screen_distance: float, dpi: float | None = None) -> np.ndarray:
    from PIL import Image

    buffer = io.BytesIO()
    with _StereoCameras(fig, eye_separation, screen_distance) as cameras:
        cameras.set_eye(eye)
        fig.savefig(buffer, format="png", dpi=dpi)
    buffer.seek(0)
    with Image.open(buffer) as image:
        return np.asarray(image.convert("RGB"))


def _combine(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    if left.shape != right.shape:
        raise ValueError("both eye images must have the same dimensions")
    height, width, channels = left.shape
    combined = np.empty((height, width * 2, channels), dtype=left.dtype)
    combined[:, :width] = left
    combined[:, width:] = right
    return combined


def _array_to_image(array: np.ndarray):
    from PIL import Image

    return Image.fromarray(array, mode="RGB")


def save_stereo_figure(fig: Figure, filepath: str | Path, *,
                       eye_separation: float = 65.0,
                       screen_distance: float = 350.0,
                       dpi: float | None = None) -> Path:
    """Render and join a still figure as full-size left-then-right stereo."""
    filepath = Path(filepath)
    left = _eye_array(fig, "left", eye_separation, screen_distance, dpi)
    right = _eye_array(fig, "right", eye_separation, screen_distance, dpi)
    _array_to_image(_combine(left, right)).save(filepath)
    return filepath


def iter_stereo_frames(animation: FuncAnimation, *,
                       eye_separation: float = 65.0,
                       screen_distance: float = 350.0,
                       dpi: float | None = None) -> Iterable[np.ndarray]:
    """Yield full-size left-then-right images for each FuncAnimation frame."""
    if animation._init_func is not None:
        animation._init_func()
    for frame_data in animation.new_frame_seq():
        animation._func(frame_data, *animation._args)
        yield _combine(
            _eye_array(animation._fig, "left", eye_separation,
                       screen_distance, dpi),
            _eye_array(animation._fig, "right", eye_separation,
                       screen_distance, dpi),
        )


def save_stereo_frames(animation: FuncAnimation, directory: str | Path, *,
                       pattern: str = "frame_{:05d}.png",
                       eye_separation: float = 65.0,
                       screen_distance: float = 350.0,
                       dpi: float | None = None) -> list[Path]:
    """Save each animation frame as a full-size side-by-side PNG."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    paths = []
    for index, frame in enumerate(iter_stereo_frames(
            animation, eye_separation=eye_separation,
            screen_distance=screen_distance, dpi=dpi)):
        path = directory / pattern.format(index)
        _array_to_image(frame).save(path)
        paths.append(path)
    return paths


def save_stereo_video(animation: FuncAnimation, filepath: str | Path, *,
                      fps: float = 30.0,
                      eye_separation: float = 65.0,
                      screen_distance: float = 350.0,
                      dpi: float | None = None,
                      ffmpeg: str = "ffmpeg") -> Path:
    """Write a side-by-side animation with the format's stereo metadata."""
    filepath = Path(filepath)
    suffix = filepath.suffix.lower()
    if suffix not in {".mkv", ".mp4", ".m4v"}:
        raise ValueError("video output must be .mkv, .mp4, or .m4v")

    frames = iter_stereo_frames(
        animation, eye_separation=eye_separation,
        screen_distance=screen_distance, dpi=dpi,
    )
    first = next(frames, None)
    if first is None:
        raise ValueError("animation has no frames")
    height, width, _ = first.shape

    command = [
        ffmpeg, "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{width}x{height}",
        "-r", str(fps), "-i", "-",
        "-pix_fmt", "yuv420p", "-x264-params", "frame-packing=3",
    ]
    if suffix == ".mkv":
        command += [
            "-c:v", "libx264", "-preset", "medium", "-crf", "18",
            "-metadata:s:v:0", "stereo_mode=1",
        ]
    else:
        command += [
            "-c:v", "libx264", "-preset", "medium", "-crf", "18",
        ]
    command += [str(filepath)]

    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    try:
        process.stdin.write(first.tobytes())
        for frame in frames:
            if frame.shape != first.shape:
                raise ValueError("all animation frames must have the same size")
            process.stdin.write(frame.tobytes())
    finally:
        process.stdin.close()
        return_code = process.wait()
    if return_code:
        raise subprocess.CalledProcessError(return_code, command)
    return filepath
