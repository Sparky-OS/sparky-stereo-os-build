#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Measure the menu bar and dock variant in the captures: layout, glass, depth per element, and the Magic Lamp window's depth over time."""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "evidence"
WALL = np.array([126, 143, 134])


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(int)


def displacement(left, right, box, span=14):
    x0, y0, x1, y1 = box
    ref = left[y0:y1, x0:x1]
    best = min(((np.abs(ref - right[y0:y1, x0 + o:x1 + o]).mean(), o) for o in range(-span, span + 1)))
    return {"right_minus_left_pixels": best[1], "mean_abs_error": round(float(best[0]), 3)}


def bbox(mask):
    ys, xs = np.nonzero(mask)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def main():
    result = {}
    panels = json.loads((EV / "m3-breeze-menubar-2d/panels.json").read_text())
    result["panels"] = panels
    top, dock = [p for p in panels if p["location"] == "top"][0], [p for p in panels if p["location"] == "bottom"][0]
    assert top["floating"] is False and top["lengthMode"] == "fill" and "org.kde.plasma.appmenu" in top["widgets"]
    assert top["widgets"][0] == "org.kde.plasma.kickoff" and top["widgets"][-1] == "org.kde.plasma.digitalclock"
    assert dock["floating"] is True and dock["lengthMode"] == "fit" and dock["alignment"] == "center" and "org.kde.plasma.icontasks" in dock["widgets"]
    desk = load(EV / "m3-breeze-menubar-2d/desktop.png")
    h, w, _ = desk.shape
    # the dock: the columns of the bottom rows that are not wallpaper, found on a row through the icons
    row = desk[960]
    away = np.abs(row - WALL).sum(axis=1) > 40
    xs = np.nonzero(away)[0]
    dock_box = (int(xs.min()), int(xs.max()))
    result["dock_columns"] = dock_box
    result["dock_centre_offset_px"] = (dock_box[0] + dock_box[1]) / 2 - w / 2
    assert abs(result["dock_centre_offset_px"]) <= 2, result
    column = desk[:, (dock_box[0] + dock_box[1]) // 2]
    gap_rows = [y for y in range(h - 1, h - 40, -1) if np.abs(column[y] - WALL).sum() < 40]
    result["dock_gap_below_px"] = len(gap_rows)
    assert len(gap_rows) >= 6, "the dock must float above the screen edge"
    # glass: between the last menu and the clock the bar is the fill over the wallpaper at 233/256
    bar = desk[10:20, 900:1400].reshape(-1, 3).mean(axis=0)
    fill = np.array([216, 217, 213])
    expected = fill * 233 / 256 + WALL * 23 / 256
    result["menu_bar_rgb"] = [round(float(v), 1) for v in bar]
    result["menu_bar_expected_rgb"] = [round(float(v), 1) for v in expected]
    assert np.abs(bar - expected).max() < 6, (bar, expected)
    # depth per eye
    left, right = load(EV / "m3-breeze-menubar-stereo/LEFT.png"), load(EV / "m3-breeze-menubar-stereo/RIGHT.png")
    boxes = {"menu bar menus": (30, 2, 720, 24), "menu bar clock and tray": (1480, 2, 1580, 24), "launcher": (14, 1, 30, 24),
             "dock": (dock_box[0] + 4, 932, dock_box[1] - 4, 990), "active window (Kate)": (40, 460, 780, 810), "inactive window (Konsole)": (40, 60, 770, 410),
             "inactive window (System Settings)": (820, 445, 1560, 800)}
    depth = {name: displacement(left, right, box) for name, box in boxes.items()}
    result["depth"] = depth
    (EV / "m3-check.json").write_text(json.dumps(result, indent=2) + "\n")
    for name, value in depth.items():
        print(name, value)
    # Magic Lamp: the left edge of the minimising window (what differs from the frame after it is gone, left of x = 540 where only it is), per eye
    lamp = EV / "m3-breeze-menubar-stereo-lamp"
    times = json.loads((lamp / "lamp-times.json").read_text())["seconds_after_minimise"]
    after_l, after_r = load(lamp / "after-LEFT.png"), load(lamp / "after-RIGHT.png")
    series = []
    for i, t in enumerate(times):
        fl, fr = load(lamp / f"lamp-{i:02d}-LEFT.png"), load(lamp / f"lamp-{i:02d}-RIGHT.png")
        ml, mr = np.abs(fl - after_l).sum(axis=2) > 60, np.abs(fr - after_r).sum(axis=2) > 60
        for m in (ml, mr):
            m[:30], m[925:], m[:, 540:] = False, False, False
        rows = [y for y in range(30, 925) if ml[y].any() and mr[y].any()]
        if len(rows) < 8:
            series.append({"t": t, "visible": False})
            continue
        shifts = [int(np.nonzero(mr[y])[0].min() - np.nonzero(ml[y])[0].min()) for y in rows]
        series.append({"t": t, "visible": True, "rows": len(rows), "left_edge_disparity_median": float(np.median(shifts)), "left_edge_disparity_min": min(shifts), "left_edge_disparity_max": max(shifts)})
    (EV / "m3-lamp-depth.json").write_text(json.dumps(series, indent=2) + "\n")
    for entry in series:
        print(entry)


if __name__ == "__main__":
    main()
