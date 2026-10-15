#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""GTK 3 and GTK 4 windows must paint with the KDE scheme's colours, and sit at their Qt neighbours' depth."""
import configparser
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence"
SLOT = {"gtk3": 0, "konsole": 1, "dolphin": 2, "kate": 3, "settings": 4, "gtk4": 5}


def scheme_colour(path, group, key):
    scheme = configparser.ConfigParser(interpolation=None)
    scheme.optionxform = str
    scheme.read(path)
    return tuple(int(v) for v in scheme[group][key].split(",")[:3])


def blend(colour, wallpaper, alpha):
    return tuple(round(c * alpha + w * (1 - alpha)) for c, w in zip(colour, wallpaper))


def near(a, b, tolerance=3):
    return all(abs(x - y) <= tolerance for x, y in zip(a, b))


def box(slot):
    return 35 + (slot % 3) * 510, 55 + (slot // 3) * 420


def edges(image, slot):
    x0, y0 = box(slot)
    grey = image.convert("L").crop((x0 - 30, y0, x0 + 530, y0 + 395))
    pixels = grey.load()
    return [[abs(pixels[x + 1, y] - pixels[x, y]) for x in range(grey.width - 1)] for y in range(grey.height)]


def shift(left, right, slot):
    """Horizontal shift of the window between the eyes, from its edge map (flat areas do not vote)."""
    x0, y0 = box(slot)
    window_left = edges(left, slot)
    best = None
    for dx in range(-24, 25):
        shifted = edges(right.crop((dx, 0, right.width + dx, right.height)), slot)
        total = sum(abs(a - b) for rl, rr in zip(window_left[20:380:3], shifted[20:380:3]) for a, b in zip(rl[40:500:2], rr[40:500:2]))
        if best is None or total < best[0]:
            best = (total, dx)
    return best[1]


def main():
    results, ok = {}, True
    for look, scheme, case in (("kubabbar-glass", ROOT / "share/color-schemes/kubabbar-glass.colors", "m2-breeze-classic"),
                               ("oxygen", Path("/usr/share/color-schemes/OxygenDark.colors"), "m2-oxygenqt-oxygen")):
        image = Image.open(EVIDENCE / (case + "-2d/desktop.png")).convert("RGB")
        wallpaper = image.getpixel((5, 5))
        view = scheme_colour(scheme, "Colors:View", "BackgroundNormal")
        selection = scheme_colour(scheme, "Colors:Selection", "BackgroundNormal")
        gx, gy = box(SLOT["gtk3"])
        hx, hy = box(SLOT["gtk4"])
        checks = {
            "gtk3 view background (inactive window, 91 %)": (image.getpixel((gx + 365, gy + 245)), blend(view, wallpaper, 232 / 255)),
            "gtk4 view background (active window, opaque)": (image.getpixel((hx + 245, hy + 225)), view),
        }
        row = None
        for y in range(hy + 40, hy + 200):
            if near(image.getpixel((hx + 100, y)), selection, 2):
                row = y
                break
        checks["gtk4 selected row (active window, opaque)"] = (image.getpixel((hx + 100, row)) if row else None, selection)
        results[look] = {}
        for name, (got, want) in checks.items():
            good = got is not None and near(got, want)
            ok &= good
            results[look][name] = {"got": got, "want": want, "pass": good}
        stereo = EVIDENCE / (case + "-stereo/desktop.png")
        if stereo.exists():
            both = Image.open(stereo).convert("RGB")
            half = both.width // 2
            left, right = both.crop((0, 0, half, both.height)), both.crop((half, 0, both.width, both.height))
            disparity = {name: shift(left, right, slot) for name, slot in SLOT.items()}
            results[look]["disparity_right_minus_left"] = disparity
            qt_inactive = [disparity[n] for n in ("konsole", "dolphin", "kate", "settings")]
            rule = {"active GTK 4 window at the screen (0)": disparity["gtk4"] == 0,
                    "inactive GTK 3 window within the inactive Qt windows' range": min(qt_inactive) <= disparity["gtk3"] <= max(qt_inactive) + 1}
            results[look]["depth_rule"] = rule
            ok &= all(rule.values())
    (EVIDENCE / "gtk-check.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
