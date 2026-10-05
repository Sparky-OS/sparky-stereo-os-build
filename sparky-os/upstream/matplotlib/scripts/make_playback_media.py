#!/usr/bin/env python3
"""Write the playing proof's media: the test plot with markers big enough to
survive video coding, as Matroska and MP4, plus the stereo frames."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np
from matplotlib.animation import FuncAnimation

import prove_stereo
from mpl_parallel_stereo import save_stereo_frames, save_stereo_video


def place_markers(axis_3d, scatter, spread=0.12):
    """Centre, near and far markers at their depths, the near one raised and
    the far one lowered on the screen so big markers do not hide each other;
    the spread grows with the frame number so each frame can be told apart."""
    centre, near, far = prove_stereo.depth_points(axis_3d)
    lift = np.array([0.0, 0.0, spread * np.ptp(axis_3d.get_zlim3d())])
    points = np.array([centre, near + lift, far - lift])
    scatter._offsets3d = (points[:, 0], points[:, 1], points[:, 2])


def update(frame, axis_3d, scatter):
    axis_3d.view_init(elev=30, azim=-60 + 12 * frame)
    place_markers(axis_3d, scatter, spread=0.08 + 0.04 * frame)


def main():
    output = Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    figure, axis_3d, _, scatter = prove_stereo.create_figure(marker_size=60)
    place_markers(axis_3d, scatter, spread=0.08)
    animation = FuncAnimation(figure, update, frames=4, fargs=(axis_3d, scatter),
                              cache_frame_data=False)
    save_stereo_frames(animation, output / "frames")
    save_stereo_video(animation, output / "stereo.mkv", fps=4)
    save_stereo_video(animation, output / "stereo.mp4", fps=4)


if __name__ == "__main__":
    main()
