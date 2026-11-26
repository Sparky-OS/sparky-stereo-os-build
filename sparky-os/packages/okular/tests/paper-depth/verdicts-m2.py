#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Check the installed milestone 2 captures and their red controls."""
import json
import math
from pathlib import Path
import re
import sys

red, green = (Path(path) for path in sys.argv[1:])
failures = 0


def check(label, actual, expected):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'} {label}: {actual!r} (expected {expected!r})")


def read(directory, case, name="measure.json"):
    return json.loads((directory / case / name).read_text())


def marks(data, kind):
    if kind == "desk" and data.get("desk"):
        shift = data["desk"]["shift"]
        return [shift] if shift is not None else []
    return [page[kind]["shift"] for page in data["measures"] if page.get(kind) and page[kind]["shift"] is not None]


def match_all(label, actual, expected):
    check(label, bool(actual) and all(value == expected for value in actual), True)
    print(f"     measured {actual!r} against {expected!r}")


def element_events(directory, case):
    log = (directory / case / "wire.txt").read_text()
    return [tuple(float(value) for value in args.split(","))
            for args in re.findall(r"\.element_limit\(([^()]*)\)", log)]


def protocol_fixed(value):
    return round(value * 256) / 256


# The EDID's 530 × 300 mm framed size and the SBS virtual mode's headset kind.
reference_distance = round(600 + (math.hypot(531, 299) - 500) * 1.8)
factor = 700 / reference_distance * (531 / 530) * 2.5
for case in ("okular-display", "preview-display"):
    old = read(red, case)
    new = read(green, case)
    match_all(f"{case} old unscaled desk", marks(old, "desk"), -6)
    match_all(f"{case} desk for known output", marks(new, "desk"), -round(6 * factor))
    match_all(f"{case} paper at the window plane", marks(new, "paper"), 0)
    expected = protocol_fixed(6 * factor)
    check(f"{case} wire carries the output steps", (expected, expected) in element_events(green, case), True)

old = read(red, "probe-override")
new = read(green, "probe-override")
check("probe behind with old policy", old["behind"]["shift"], -3)
check("probe in front with old policy", old["in_front"]["shift"], 3)
check("probe behind with display policy", new["behind"]["shift"], -round(3 * factor))
check("probe in front with one-direction override", new["in_front"]["shift"], 12)
check("asymmetric element_limit on the wire",
      (protocol_fixed(3 * factor), 12.0) in element_events(green, "probe-override"), True)

check("ElementLimit saved by the page", "ElementLimit=6" in (green / "okular-kcm/kwinrc").read_text().splitlines(), True)
check("Element limit page changed the wire", (6.0, 6.0) in element_events(green, "okular-kcm"), True)
match_all("Element limit page moved the desk", marks(read(green, "okular-kcm"), "desk"), -6)

for label, directory, expected in (("Debian Words", red, 0), ("Stereo Words", green, -6)):
    data = read(directory, "words-3d")
    check(f"{label} two visible pages", len(data["pages"]), 2)
    match_all(f"{label} paper", marks(data, "paper"), 0)
    match_all(f"{label} desk", marks(data, "desk"), expected)

data = read(green, "words-scrolled")
cut = [page for page in data["measures"] if page.get("paper_at_cut")]
check("Words page under the toolbar", bool(cut), True)
match_all("Words page under the toolbar depth", [page["paper_at_cut"]["shift"] for page in cut], 0)
check("Words page edge under the toolbar is the same in both eyes",
      bool(cut) and all(None not in page["right_edge_at_cut"] and len(set(page["right_edge_at_cut"])) == 1 for page in cut), True)
background = read(green, "words-background")
background_shift = (background.get("title_bar") or {}).get("shift")
check("Words background title-bar disparity measured", background_shift is not None, True)
match_all("Words background paper follows the window", marks(background, "paper"), background_shift)
match_all("Words background desk follows the window", marks(background, "desk"), background_shift)
check("Words 2D output matches Debian pixel for pixel", read(green, "words-2d", "baseline.json")["differing"], 0)

sys.exit(1 if failures else 0)
