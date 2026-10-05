#!/usr/bin/env python3
"""Check a KWin capture of the stereo test video playing in mpv.

The capture of a stereo window is the two views side by side, each as wide as
the screen.  The video (itself side by side, left eye first) is shown inside
each view, scaled; the markers of the test plot are found by colour, mapped
back to the source frame's pixels and compared with the source frames.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

MARKER_COLOURS = {
    "centre": (255, 0, 255),
    "near": (0, 255, 0),
    "far": (0, 0, 255),
}
TOLERANCE = 1.0  # pixels of the source eye image
COLOUR_DISTANCE = 100
BLACK = 12


def marker_centroid(image, colour):
    difference = np.abs(image.astype(int) - np.asarray(colour, dtype=int))
    matches = np.all(difference <= COLOUR_DISTANCE, axis=-1)
    if not np.any(matches):
        raise RuntimeError(f"marker not found: {colour}")
    y_pixels, x_pixels = np.nonzero(matches)
    return np.array([x_pixels.mean(), y_pixels.mean()])


def content_box(view):
    """Bounding box (x0, y0, x1, y1) of the non-black picture in one view."""
    ys, xs = np.nonzero(np.any(view > BLACK, axis=-1))
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def eye_markers(eye):
    return {name: marker_centroid(eye, colour)
            for name, colour in MARKER_COLOURS.items()}


def load_sources(directory):
    sources = []
    for path in sorted(Path(directory).glob("*.png")):
        with Image.open(path) as source:
            frame = np.asarray(source.convert("RGB"))
        half = frame.shape[1] // 2
        sources.append({"left": frame[:, :half], "right": frame[:, half:]})
    return sources


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("capture")
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--mpv-log", required=True)
    parser.add_argument("--frames", required=True,
                        help="directory of the source stereo frames (PNG)")
    parser.add_argument("--view-width", type=int, default=1024)
    args = parser.parse_args()

    with Image.open(args.capture) as source:
        image = np.asarray(source.convert("RGB"))
    height, width, _ = image.shape
    views = {"left": image[:, :width // 2], "right": image[:, width // 2:]}

    with open(args.metadata, encoding="utf-8") as source:
        kwin_stereo = json.load(source).get("stereo", "")
    with open(args.mpv_log, encoding="utf-8", errors="replace") as source:
        lines = source.read().splitlines()
    set_content = sum(1 for line in lines
                      if "kde_stereo_content_v1#" in line and ".set_content(" in line)

    sources = load_sources(args.frames)
    source_height, source_width = sources[0]["left"].shape[:2]

    boxes = {eye: content_box(view) for eye, view in views.items()}
    scales = {eye: (box[2] - box[0]) / source_width for eye, box in boxes.items()}
    # Marker positions in source-eye pixels, from each captured view.
    captured = {}
    for eye, view in views.items():
        x0, y0, x1, y1 = boxes[eye]
        markers = eye_markers(view[y0:y1, x0:x1])
        captured[eye] = {name: point / scales[eye] for name, point in markers.items()}

    matched = {}
    for eye in ("left", "right"):
        errors = []
        for frame in sources:
            reference = eye_markers(frame[eye])
            errors.append(max(float(np.abs(captured[eye][name] - reference[name]).max())
                              for name in MARKER_COLOURS))
        best = int(np.argmin(errors))
        matched[eye] = {"frame": best, "max_error_px": errors[best]}

    disparity = {name: (captured["left"][name] - captured["right"][name])
                 for name in MARKER_COLOURS}
    source_disparity = {}
    if matched["left"]["frame"] == matched["right"]["frame"]:
        frame = sources[matched["left"]["frame"]]
        left, right = eye_markers(frame["left"]), eye_markers(frame["right"])
        source_disparity = {name: left[name] - right[name] for name in MARKER_COLOURS}

    # The 2D axes (figure fractions x 0.02..0.22, y 0.12..0.70 from the bottom).
    def two_d(eye):
        x0, y0, x1, y1 = boxes[eye]
        w, h = x1 - x0, y1 - y0
        part = views[eye][y0 + int(0.30 * h):y0 + int(0.88 * h),
                          x0 + int(0.02 * w):x0 + int(0.22 * w)]
        return part.astype(int)
    two_d_left, two_d_right = two_d("left"), two_d("right")
    two_d_difference = np.abs(two_d_left - two_d_right)

    checks = {key: bool(value) for key, value in {
        "window_declared_stereo": kwin_stereo in ("1", "True", "true") and set_content > 0,
        "capture_is_two_views": width == 2 * args.view_width,
        "eye_scales_equal": abs(scales["left"] - scales["right"]) < 0.01,
        "left_eye_shows_left_view": matched["left"]["max_error_px"] <= TOLERANCE,
        "right_eye_shows_right_view": matched["right"]["max_error_px"] <= TOLERANCE,
        "same_frame_in_both_eyes": matched["left"]["frame"] == matched["right"]["frame"],
        "centre_x_zero": abs(disparity["centre"][0]) <= TOLERANCE,
        "near_x_positive": disparity["near"][0] > TOLERANCE,
        "far_x_negative": disparity["far"][0] < -TOLERANCE,
        "vertical_zero": all(abs(d[1]) <= TOLERANCE for d in disparity.values()),
        "two_d_same_in_both_eyes": float(two_d_difference.mean()) <= 2.0,
    }.items()}
    result = {
        "capture": args.capture,
        "capture_size": [width, height],
        "view_size": [width // 2, height],
        "declared": {"kwin_capture_stereo": kwin_stereo,
                     "mpv_set_content_calls": set_content},
        "picture_box_per_view": {eye: [int(v) for v in box] for eye, box in boxes.items()},
        "scale_to_source": scales,
        "source_eye_size": [source_width, source_height],
        "captured_markers_source_px": {
            eye: {name: point.tolist() for name, point in markers.items()}
            for eye, markers in captured.items()},
        "frame_match": matched,
        "disparity_px": {name: value.tolist() for name, value in disparity.items()},
        "source_disparity_px": {name: value.tolist()
                                for name, value in source_disparity.items()},
        "two_d_region_pixels": int(two_d_left.shape[0] * two_d_left.shape[1]),
        "two_d_mean_abs_difference": float(two_d_difference.mean()),
        "two_d_max_abs_difference": int(two_d_difference.max()),
        "tolerance_px": TOLERANCE,
        "checks": checks,
    }
    with open(args.evidence, "w", encoding="utf-8") as output:
        json.dump(result, output, indent=2, sort_keys=True)
        output.write("\n")
    print(json.dumps({"checks": checks, "disparity_px": result["disparity_px"],
                      "frame_match": matched}, indent=2, sort_keys=True))
    if not all(checks.values()):
        raise SystemExit("playback capture verification failed")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        raise SystemExit(f"playback capture verification failed: {error}")
