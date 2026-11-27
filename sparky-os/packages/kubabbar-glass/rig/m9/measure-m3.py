#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""measure-m3.py OUT RIG: the rows of Kubabbar Glass 9 milestone 3's proof (queue row 147, with row 945) from
rerun-m3.sh's cases in OUT/before and OUT/after (RIG: the stereo-proof-rig scripts, for mark_pns.py). One line per row,
PASS or FAIL; a case not run gives no rows. A "red" row passes when the before image shows the fault this milestone
removes, so the same check is known to be able to fail."""
import json
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image

OUT, RIG = sys.argv[1], sys.argv[2]
rows = []


def row(ok, text):
    rows.append(("PASS" if ok else "FAIL") + " " + text)


def case(side, name):
    d = os.path.join(OUT, side, name)
    return d if os.path.isdir(d) else None


def load(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return None


def find(d, name):
    for root, _, files in os.walk(d or ""):
        if name in files:
            return os.path.join(root, name)
    return None


def mark(src, dst):
    if src and os.path.exists(src):
        subprocess.run(["python3", os.path.join(RIG, "mark_pns.py"), src, os.path.join(OUT, dst)], check=False)


# ---------------------------------------------------------------- GTK 4's steppers in a real window
for side in ("before", "after"):
    d = case(side, "steppers")
    if not d:
        continue
    res = load(os.path.join(d, "steppers.json")) or []
    failed = [r["row"] for r in res if not r["passed"]]
    if side == "before":
        nodes = next((r for r in res if r["row"] == "nodes"), {})
        row(bool(res) and failed == ["nodes"], f"steppers-red: the before image's GTK 4 has no stepper nodes ({nodes.get('nodes')})")
    else:
        row(len(res) == 14 and not failed, f"steppers: {len(res) - len(failed)} of {len(res)} rows from the installed GTK 4 "
            f"(order, no room without a theme rule, both placements, sensitivity, right to left, click, hold, page, middle)"
            + (f"; failed {failed}" if failed else ""))
        for r in res:
            if r["row"] in ("together-sizes", "apart-sizes", "hold-keeps-scrolling", "middle-jumps-to-end"):
                facts = {k: v for k, v in r.items() if k not in ("row", "passed")}
                rows.append(f"  {r['row']}: {json.dumps(facts)}")

# ---------------------------------------------------------------- GTK galleries in both placements
for side in ("before", "after"):
    d = case(side, "gtk")
    if not d:
        continue
    lines = open(os.path.join(d, "rows.txt")).read().splitlines() if os.path.exists(os.path.join(d, "rows.txt")) else []
    gtk4 = [l for l in lines if " gtk4-" in l]
    rest = [l for l in lines if " gtk4-" not in l]
    if side == "before":
        row(len(gtk4) == 2 and all(l.startswith("FAIL") for l in gtk4) and all(l.startswith("PASS") for l in rest),
            f"gtk-red: on the before image only GTK 4 lacks the arrows ({len(gtk4)} GTK 4 rows FAIL, {len(rest)} others PASS)")
    else:
        row(len(lines) >= 13 and all(l.startswith("PASS") for l in lines), f"gtk: {sum(l.startswith('PASS') for l in lines)} of "
            f"{len(lines)} gallery rows: GTK 2, 3 and 4 show the arrows together, then apart, beside Qt 6; the Breeze control fails")
        rows.extend("  " + l for l in gtk4)

# ---------------------------------------------------------------- other themes unchanged: GTK 4 in Breeze and GTK's own
b, a = case("before", "gtk-default"), case("after", "gtk-default")
if b and a:
    for theme in ("Breeze", "Default"):
        pb, pa = os.path.join(b, f"gtk4-{theme}-window.png"), os.path.join(a, f"gtk4-{theme}-window.png")
        rb, ra = load(os.path.join(b, f"gtk4-{theme}.json")), load(os.path.join(a, f"gtk4-{theme}.json"))
        if not (os.path.exists(pb) and os.path.exists(pa) and rb and ra):
            row(False, f"gtk-default-{theme}: a capture or report is missing")
            continue
        ib, ia = np.asarray(Image.open(pb).convert("RGB")).astype(int), np.asarray(Image.open(pa).convert("RGB")).astype(int)
        diff = np.abs(ib - ia).max(axis=2) > 0
        bar_px = 0
        for x, y, w, h in ra["bars"].values():
            bar_px += int(diff[y:y + h, x:x + w].sum())
        same_geometry = rb["bars"] == ra["bars"] and rb["size"] == ra["size"]
        ys, xs = np.nonzero(diff)
        box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None
        row(same_geometry and bar_px == 0 and int(diff.sum()) == 0,
            f"gtk-default-{theme}: GTK 4's gallery in {theme} before and after: {int(diff.sum())} pixels differ "
            f"(box {box}), {bar_px} in the scroll bars; bars {ra['bars']} equal: {same_geometry}")

# ---------------------------------------------------------------- the sync's tests, on the installed script
for side in ("before", "after"):
    d = case(side, "sync-test")
    if not d:
        continue
    res = load(os.path.join(d, "results", "results.json")) or []
    failed = [r["case"] for r in res if not r["passed"]]
    overlay = [r["case"] for r in res if r["case"].startswith("overlay")]
    if side == "before":
        row(bool(failed) and set(failed) <= set(overlay) and len(res) - len(overlay) == 35,
            f"sync-test-red: milestone 2's installed sync fails {len(failed)} of the {len(overlay)} overlay cases ({failed}) "
            f"and passes the other {len(res) - len(overlay)}")
    else:
        row(len(res) == 44 and not failed, f"sync-test: the installed sparky-stereo-gtk-sync passes {len(res) - len(failed)} of {len(res)} cases")

# ---------------------------------------------------------------- GTK's bars always visible in a real login
for side in ("before", "after"):
    d = case(side, "bars")
    if not d:
        continue
    g3, g4 = load(find(d, "bars-gtk3.json")), load(find(d, "bars-gtk4.json"))
    st = load(find(d, "bars-settings.json")) or {}
    if not (g3 and g4):
        row(False, f"bars-{side}: no report from the GTK programs")
        continue
    facts = {k: {"overlay": g["overlay_setting"], "classes": [c for c in g["classes"] if c in ("overlay-indicator", "hovering", "dragging")],
                 "opacity": g["opacity"], "width": g["width"], "theme": g["theme"]} for k, g in (("gtk3", g3), ("gtk4", g4))}
    if side == "before":
        row(all(g["overlay_setting"] and "overlay-indicator" in g["classes"] and g["opacity"] == 0 for g in (g3, g4)),
            f"bars-red: before, GTK 3 and 4 resolve overlay scrolling on and their idle bars are faded overlay indicators {json.dumps(facts)}")
    else:
        visible = all(not g["overlay_setting"] and "overlay-indicator" not in g["classes"] and g["opacity"] == 1 and g["mapped"]
                      for g in (g3, g4))
        row(visible and g3["theme"].startswith("Kubabbar-Glass-9") and g4["theme"].startswith("Kubabbar-Glass-9"),
            f"bars: in a login on Kubabbar Glass 9, GTK 3 and 4 bars show without hover (no overlay indicator, opacity 1) {json.dumps(facts)}")
        row(g4["steppers"] is not None and [s[1] for s in g4["steppers"]] == [0, 0, 16, 16],
            f"bars-gtk4-arrows: the GTK 4 program's bar has its arrows together at the end (stepper heights {[s[1] for s in g4['steppers'] or []]})")
        ini = [st.get(f) or "" for f in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini")]
        row(all("gtk-overlay-scrolling=false" in i for i in ini) and st.get("dconf") == "false"
            and st.get("record") == "gtk-3.0 false\ngtk-4.0 false\ngsettings false\n",
            f"bars-settings: the sync wrote both settings.ini files and the GSettings key (dconf {st.get('dconf')!r}) and recorded them; "
            f"settings portal on the bus: {st.get('portal_on_bus')} {st.get('portal_backends_on_bus')}")

# ---------------------------------------------------------------- the family's login screen labelled
TEXT = np.array((27, 33, 25))  # the theme's text colour, #1b2119


def label_pixels(img):
    """Text-coloured pixels inside the theme's panel (440 x 330, centred on 1920 x 1080), title bar excluded."""
    panel = img[375 + 30:375 + 330, 740:740 + 440].astype(int)
    return int((np.abs(panel - TEXT).max(axis=2) <= 40).sum())


for side in ("before", "after"):
    for mode in ("2d", "3d"):
        d = case(side, f"greeter-family-{mode}")
        if not d:
            continue
        log = open(find(d, "greeter-family.log")).read() if find(d, "greeter-family.log") else ""
        errors = len(re.findall(r"ReferenceError: textConstants is not defined", log))
        shotp = find(d, "greeter-family.png")
        if not shotp:
            row(False, f"greeter-family-{mode}-{side}: no capture")
            continue
        img = np.asarray(Image.open(shotp).convert("RGB"))
        eyes = [img] if mode == "2d" else [img[:, :img.shape[1] // 2], img[:, img.shape[1] // 2:]]
        counts = [label_pixels(e) for e in eyes]
        if side == "before":
            row(errors >= 5, f"greeter-family-{mode}-red: the published theme logs {errors} 'textConstants is not defined' "
                f"(text-coloured pixels in its panel: {counts})")
        else:
            before = case("before", f"greeter-family-{mode}")
            bshot = find(before, "greeter-family.png") if before else None
            bcounts = None
            if bshot:
                bimg = np.asarray(Image.open(bshot).convert("RGB"))
                beyes = [bimg] if mode == "2d" else [bimg[:, :bimg.shape[1] // 2], bimg[:, bimg.shape[1] // 2:]]
                bcounts = [label_pixels(e) for e in beyes]
            more = bcounts is not None and all(c >= bc + 300 for c, bc in zip(counts, bcounts))
            same_eyes = mode == "2d" or abs(counts[0] - counts[1]) <= max(20, counts[0] // 50)
            row(errors == 0 and more and same_eyes,
                f"greeter-family-{mode}: the new theme logs {errors} errors and its labels are drawn (text-coloured pixels "
                f"{counts} against {bcounts} before" + ("" if mode == "2d" else ", in both eyes") + ")")
            if mode == "3d":
                mark(shotp, "greeter-family-3d.pns")
                mark(bshot, "greeter-family-3d-before.pns")
            else:
                Image.open(shotp).save(os.path.join(OUT, "greeter-family-2d.png"))
                if bshot:
                    Image.open(bshot).save(os.path.join(OUT, "greeter-family-2d-before.png"))

# ---------------------------------------------------------------- the dock's browser
for side in ("before", "after"):
    for look in ("family", "9"):
        d = case(side, f"dock-{look}")
        if not d:
            continue
        data = load(find(d, "dock.json")) or []
        launchers = [l for e in data for l in e.get("launchers", [])]
        present = {k: v for e in data for k, v in e.get("present", {}).items()}
        browsers = [l for l in launchers if "firefox" in l or "browser" in l]
        if side == "before":
            row("applications:firefox.desktop" in launchers and not present.get("applications:firefox.desktop"),
                f"dock-{look}-red: the before dock names {browsers}, whose entry the system does not have")
        else:
            row("applications:sparky-stereo-browser.desktop" in launchers and present.get("applications:sparky-stereo-browser.desktop")
                and not any("firefox" in l for l in launchers),
                f"dock-{look}: the dock names {browsers}, installed: {[present.get(b) for b in browsers]}")
            shotp = find(d, "dock-shot.png")
            if shotp:
                Image.open(shotp).save(os.path.join(OUT, f"dock-{look}.png"))

print("\n".join(rows))
