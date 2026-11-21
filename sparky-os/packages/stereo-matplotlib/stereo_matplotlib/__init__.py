# SPDX-License-Identifier: MIT
"""Matplotlib's 3D plots in stereo on Sparky Stereo OS.

    import matplotlib.pyplot as plt
    import stereo_matplotlib

    fig = plt.figure()
    ax = fig.add_subplot(projection='3d')
    ...
    stereo_matplotlib.show()                        # every open figure, its 3D area as a declared pair
    stereo_matplotlib.save_stereo_figure(fig, 'plot.pns')   # PNG with sTER, or .jps for JPEG with the JPS block

Every Axes3D gets two parallel cameras (never toe-in) whose offset is fitted, never set: the largest offset for which
every point the figure draws stays inside the person's depth limits, read from the one place (Stereo KWin hands them
to the figure's window; an export uses the window's when the figure is shown in 3D, otherwise the person's own numbers
from the desktop's 3D Depth settings, as pixels of a view 1920 wide).  2D parts of the figure are the same in both
eyes.  The module lives outside Matplotlib; it reads Matplotlib 3.10's 3D projection and says so when that changes.
"""
import configparser
import os
from pathlib import Path

import numpy as np

from . import cameras, writers
from .cameras import InternalsChanged, StereoCameras, fit, projected_points
from .figure3d import StereoFigure, render_pair, tell
from .writers import StereoFileExists, write_jps, write_pns

__all__ = ['show', 'StereoFigure', 'save_stereo_figure', 'iter_stereo_frames', 'save_stereo_frames',
           'save_stereo_video', 'render_pair', 'person_limits', 'StereoFileExists', 'InternalsChanged']
__version__ = '0.1.1'

KWIN_DEFAULT_LIMITS = (10.0, 4.0)   # SunkLimit, PoppedLimit of Stereo KWin's [StereoDepth], a view 1920 wide

_figures = {}


def show(*args, **kwargs):
    """plt.show() with every open figure's 3D area shown as a declared pair (Enable 3D on, by default)."""
    import matplotlib.pyplot as plt
    for number in plt.get_fignums():
        figure = plt.figure(number)
        if figure not in _figures:
            _figures[figure] = StereoFigure(figure)
    return plt.show(*args, **kwargs)


def person_limits():
    """The person's own numbers from the one place (kwinrc [StereoDepth]), a view 1920 wide, KWin's defaults when unset."""
    config = configparser.ConfigParser(strict=False, interpolation=None)
    home = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    try:
        config.read(os.path.join(home, 'kwinrc'), encoding='utf-8')
        sunk = config.getfloat('StereoDepth', 'SunkLimit', fallback=KWIN_DEFAULT_LIMITS[0])
        popped = config.getfloat('StereoDepth', 'PoppedLimit', fallback=KWIN_DEFAULT_LIMITS[1])
    except (configparser.Error, ValueError):
        sunk, popped = KWIN_DEFAULT_LIMITS
    return sunk, popped


def _export_limits(figure, eye_width):
    """Limits in the pixels of an exported eye eye_width wide.  Shown in 3D: the window's limits times the buffer
    over the width it is shown at (the one conversion the rule allows); otherwise the person's numbers, the picture
    taken as shown a view 1920 wide."""
    shown = _figures.get(figure)
    if shown is not None and shown.area is not None and shown.limits:
        scale = eye_width / float(shown.area.width)
        return shown.limits[0] * scale, shown.limits[1] * scale
    sunk, popped = person_limits()
    return sunk * eye_width / 1920.0, popped * eye_width / 1920.0


def _pair_at(figure, dpi):
    old = figure.dpi
    if dpi and dpi != old:
        figure._set_dpi(dpi, forward=False)
    try:
        width, height = int(round(figure.bbox.width)), int(round(figure.bbox.height))
        left, right, offsets = render_pair(figure, _export_limits(figure, width), width, height, figure.dpi)
    finally:
        if dpi and dpi != old:
            figure._set_dpi(old, forward=False)
    return left, right


def save_stereo_figure(figure, path, *, dpi=None, replace=False):
    """Write the figure's pair to a new file: .pns (PNG with sTER) or .jps (JPEG with the JPS block)."""
    suffix = Path(path).suffix.lower()
    if suffix not in ('.pns', '.jps'):
        raise ValueError('a stereo figure is written as .pns or .jps')
    if os.path.lexists(path) and not replace:
        raise StereoFileExists(os.fspath(path))
    left, right = _pair_at(figure, dpi)
    if suffix == '.pns':
        return write_pns(path, left, right, replace=replace)
    return write_jps(path, left, right, replace=replace)


def iter_stereo_frames(animation, *, dpi=None):
    """(left, right) for every frame of a FuncAnimation."""
    if animation._init_func is not None:
        animation._init_func()
    for frame in animation.new_frame_seq():
        animation._func(frame, *animation._args)
        yield _pair_at(animation._fig, dpi)


def save_stereo_frames(animation, directory, *, pattern='frame_{:05d}.pns', dpi=None, replace=False):
    """Every frame as a .pns file in a folder; only new files are written unless replace is True."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    paths = []
    for index, (left, right) in enumerate(iter_stereo_frames(animation, dpi=dpi)):
        paths.append(write_pns(directory / pattern.format(index), left, right, replace=replace))
    return paths


def save_stereo_video(animation, path, *, fps=30.0, dpi=None, ffmpeg='ffmpeg', replace=False):
    """A side-by-side video, left eye first, marked: the frame packing SEI (type 3, x264's frame-packing=3) and, in
    Matroska, StereoMode 1."""
    import subprocess
    path = Path(path)
    if path.suffix.lower() not in {'.mkv', '.mp4', '.m4v'}:
        raise ValueError('video output must be .mkv, .mp4, or .m4v')
    if os.path.lexists(path) and not replace:
        raise StereoFileExists(os.fspath(path))
    frames = iter_stereo_frames(animation, dpi=dpi)
    first = next(frames, None)
    if first is None:
        raise ValueError('animation has no frames')
    picture = np.concatenate(first, axis=1)[..., :3]
    height, width = picture.shape[:2]
    command = [ffmpeg, '-y' if replace else '-n', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
               '-s', '%dx%d' % (width, height), '-r', str(fps), '-i', '-', '-pix_fmt', 'yuv420p',
               '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-x264-params', 'frame-packing=3']
    if path.suffix.lower() == '.mkv':
        command += ['-metadata:s:v:0', 'stereo_mode=1']
    command.append(os.fspath(path))
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    try:
        process.stdin.write(np.ascontiguousarray(picture).tobytes())
        for left, right in frames:
            frame = np.concatenate([left, right], axis=1)[..., :3]
            if frame.shape != picture.shape:
                raise ValueError('all animation frames must have the same size')
            process.stdin.write(np.ascontiguousarray(frame).tobytes())
    finally:
        process.stdin.close()
        code = process.wait()
    if code:
        raise subprocess.CalledProcessError(code, command)
    return path
