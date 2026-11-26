#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""measure-m2.py OUT RIG: the rows of Kubabbar Glass 9 milestone 2's proof from rerun-m2.sh's cases in OUT (RIG: the
stereo-proof-rig scripts, for measure-regions.py, splash_regions.py and mark_pns.py). One line per row, PASS or FAIL;
a case not run gives no rows. The expected values come from the recipe: the family's glass (tools/glass_levels.py), the
look's colours (tools/platinum9.py) and KWin's default depth limits (popped 4, sunk 10 at 1920 wide; the rig saves none).
Disparities are right eye minus left eye in device pixels: popped is negative, sunk positive."""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

OUT, RIG = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
from glass_levels import BACKGROUND_ALPHA, SPARKY_BLACK_ALPHA  # noqa: E402
from platinum9 import ACCENTS, FACE, OUTLINE, PRESSED, TEXT, TEXT_INACTIVE, TOOLTIP, VIEW, contrast  # noqa: E402

POPPED, SUNK = 4, 10
rows = []


def row(ok, text):
    rows.append(("PASS" if ok else "FAIL") + " " + text)


def case(name):
    d = os.path.join(OUT, name)
    return d if os.path.isdir(d) else None


def load(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return None


def regions(pair, plain, regs, name):
    p = os.path.join(OUT, f"regions-{name}.json")
    json.dump(regs, open(p, "w"), indent=1)
    r = subprocess.run(["python3", os.path.join(RIG, "login-splash/measure-regions.py"), pair, plain, p],
                       capture_output=True, text=True)
    open(os.path.join(OUT, f"measured-{name}.json"), "w").write(r.stdout + r.stderr)
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {"error": (r.stdout + r.stderr)[-300:]}


def mark(src, dst):
    if os.path.exists(src):
        subprocess.run(["python3", os.path.join(RIG, "mark_pns.py"), src, os.path.join(OUT, dst)], check=False)


# ---------------------------------------------------------------- GTK galleries (gtk-proof.sh)
d = case("gtk")
if d:
    lines = open(os.path.join(d, "rows.txt")).read().splitlines() if os.path.exists(os.path.join(d, "rows.txt")) else []
    for line in lines:
        ok, _, text = line.partition(" ")
        row(ok == "PASS", "gtk " + text)
    if not lines:
        row(False, "gtk: no rows (gtk-proof.sh did not run)")

# ---------------------------------------------------------------- the menu bar layout
d = case("menubar-2d")
if d:
    panels = load(os.path.join(d, "panels.json")) or []
    top = [p for p in panels if p["location"] == "top"]
    dock = [p for p in panels if p["location"] == "bottom" and p["floating"]]
    want = ["org.kde.plasma.kickoff", "org.kde.plasma.appmenu", "org.kde.plasma.systemtray", "org.kde.plasma.digitalclock"]
    ok = (len(panels) == 2 and len(top) == 1 and len(dock) == 1 and all(a in top[0]["applets"] for a in want)
          and top[0]["applets"][-1] == "org.kde.plasma.windowlist" and "org.kde.plasma.icontasks" in dock[0]["applets"])
    row(ok, "menubar-layout: a new account's panels: " + "; ".join(f"{p['location']}{' floating' if p['floating'] else ''}: "
                                                                    + ", ".join(a.rsplit('.', 1)[-1] for a in p["applets"]) for p in panels))
    glass = load(os.path.join(d, "glass.json")) or {}
    expect = {"top bar": ("panel@0,0", SPARKY_BLACK_ALPHA["widgets/panel-background"]["north"]),
              "dock": ("panel@", SPARKY_BLACK_ALPHA["widgets/panel-background"]["south"]),
              "notification": ("notification", SPARKY_BLACK_ALPHA["dialogs/background"][""]),
              "launcher pop-up": ("launcher-popup", SPARKY_BLACK_ALPHA["dialogs/background"][""]),
              "inactive window": ("probe-inactive", round(BACKGROUND_ALPHA * 255 - 0.5)),
              "dialog": ("probe-dialog", round(BACKGROUND_ALPHA * 255 - 0.5))}
    for label, (key, level) in expect.items():
        if label == "dock":
            hits = [v for k, v in glass.items() if k.startswith("panel@") and not k.startswith("panel@0,0")]
        else:
            hits = [v for k, v in glass.items() if k.startswith(key)]
        got = hits[0].get("alpha_8bit_median") if hits else None
        row(got == level, f"menubar-glass: {label} {got}, the family's level {level}")

d = case("menubar-3d")
d2m = case("menubar-2d")
if d:
    pair = os.path.join(d, "panels-shot.png")
    plain = os.path.join(d2m, "panels-shot.png") if d2m else ""
    if os.path.exists(pair) and os.path.exists(plain):
        # the panels touch the screen's edges, so they stand at the screen; they are translucent over the sunk wallpaper,
        # so their pixels differ between the eyes, and only their own opaque parts are matched against the same layout's
        # 2D login: the window list at the bar's right end and the dock's icons (the clock is left out, the logins differ
        # by minutes; the bar's left part holds the launcher at the edge and an application menu only when a program has
        # one, so a box there matches the wallpaper behind the glass, +10)
        res = regions(pair, plain, [{"name": "top bar (the window list at its right end)", "box": [1786, 4, 1894, 27], "predicted": 0},
                                    {"name": "dock", "box": [600, 1004, 1320, 1074], "predicted": 0}], "menubar-3d")
        for name, v in res.items():
            if isinstance(v, dict):
                row(v.get("pass", False), f"menubar-3d: {name} disparity {v.get('observed')} (predicted 0, the screen; "
                    f"vertical {v.get('vertical_observed')})")
        if "error" in res:
            row(False, "menubar-3d: " + str(res["error"]))
        mark(pair, "menubar-3d.pns")
    else:
        row(False, "menubar-3d: no capture")

d = case("keep")
if d:
    before, after, reset = (load(os.path.join(d, f)) for f in ("panels-before.json", "panels-after-apply.json", "panels-after-reset.json"))
    row(before is not None and before == after, f"keep: the person's panels after applying the menu bar look without the layout: "
        f"{'unchanged' if before == after else 'CHANGED'} ({len(before or [])} panels)")
    ok = bool(reset) and any(p["location"] == "top" and "org.kde.plasma.windowlist" in p["applets"] for p in reset)
    row(ok, "keep-control: with --resetLayout the menu bar layout replaces them (top bar with the window list)")

# ---------------------------------------------------------------- the loading screen
d2, d3 = case("splash-2d"), case("splash-3d")
box = None
if d2:
    plain = os.path.join(d2, "shot-3s-Virtual-0.png")
    if os.path.exists(plain):
        g = np.asarray(Image.open(plain).convert("L")).astype(float)
        m = g > 150
        m[: g.shape[0] // 6] = False
        ys, xs = np.nonzero(m)
        box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())) if len(xs) else None
        log = open(os.path.join(d2, "session.log"), errors="replace").read()
        row(box is not None and 400 < box[2] - box[0] < 520, f"splash-2d: the box drawn at {box} (460 wide expected)")
        row("kubabbar-glass-9" in open(os.path.join(d2, "config-before", "kdedefaults", "ksplashrc")).read()
            if os.path.exists(os.path.join(d2, "config-before", "kdedefaults", "ksplashrc")) else False,
            "splash-2d: the look names its own loading screen (kdedefaults/ksplashrc Theme=kubabbar-glass-9)")
        errs = [ln for ln in log.splitlines() if "Splash.qml" in ln and ("rror" in ln or "not defined" in ln)]
        row(not errs, f"splash-2d: no QML error from the splash ({len(errs)}): " + " | ".join(errs[:2]))
if d2 and d3 and box:
    plain, pair = os.path.join(d2, "shot-3s-Virtual-0.png"), os.path.join(d3, "shot-3s-Virtual-0.png")
    if os.path.exists(pair):
        rp = os.path.join(OUT, "regions-splash.json")
        r = subprocess.run(["python3", os.path.join(RIG, "login-splash/splash_regions.py"), plain, pair, "window", str(POPPED), rp],
                           capture_output=True, text=True)
        bg = json.loads(r.stdout) if r.stdout.strip().startswith("{") else {"error": r.stderr[-300:]}
        regs = json.load(open(rp)) if os.path.exists(rp) else []
        res = regions(pair, plain, regs, "splash") if regs else {}
        for name, v in res.items():
            if isinstance(v, dict):
                row(v.get("pass", False), f"splash-3d: {name} disparity {v.get('observed')} (predicted {v.get('predicted')}, "
                    f"vertical {v.get('vertical_observed')})")
        row(bg.get("outside_differing", 1) == 0, f"splash-3d: the background at the screen: {bg.get('outside_differing')} of "
            f"{bg.get('outside_pixels')} pixels differ between the eyes outside the box")
        mark(pair, "splash-3d.pns")
dk, dw = case("splash-black"), case("splash-white")
if dk and dw and box:
    b = np.asarray(Image.open(os.path.join(dk, "shot-3s-Virtual-0.png")).convert("RGB")).astype(float)
    wh = np.asarray(Image.open(os.path.join(dw, "shot-3s-Virtual-0.png")).convert("RGB")).astype(float)
    x0, y0, x1, y1 = box
    face = (slice(y1 - 22, y1 - 6), slice(x0 + 12, x1 - 12))  # the box's bottom margin, below the progress bar: face only
    a = 1 - (wh[face] - b[face]) / 255.0
    level = int(round(float(np.median(a)) * 255))
    want = round(BACKGROUND_ALPHA * 255 - 0.5)
    row(abs(level - want) <= 1, f"splash-glass: the box {level}, the family's dialog glass {want} (glass_levels.BACKGROUND_ALPHA)")
    # its texts over the box, as drawn over the real background (the 2D capture): face and background measured there
    if d2:
        p = np.asarray(Image.open(os.path.join(d2, "shot-3s-Virtual-0.png")).convert("RGB")).astype(float)
        facec = np.median(p[face].reshape(-1, 3), axis=0)
        behind = (facec - BACKGROUND_ALPHA * np.array(FACE)) / (1 - BACKGROUND_ALPHA)
        worst = min(contrast(tuple(facec), tuple(BACKGROUND_ALPHA * np.array(t) + (1 - BACKGROUND_ALPHA) * behind))
                    for t in (TEXT, TEXT_INACTIVE))
        row(worst >= 4.5, f"splash-texts: lowest contrast {worst:.2f} (the name and the theme's name on the box)")

# ---------------------------------------------------------------- the login screen
def greeter_rect(d):
    wins = load(os.path.join(d, "greeter-windows.json")) or []
    if isinstance(wins, dict):
        wins = wins.get("windows", [])
    for w in wins if isinstance(wins, list) else []:
        if "greeter" in (w.get("cls", "") + w.get("caption", "")).lower():
            return w.get("cg") or w.get("fg")
    return None


g2, g3 = case("greeter-2d"), case("greeter-3d")
for d in (g2, g3):
    if d:
        log = open(os.path.join(d, "greeter.log"), errors="replace").read() if os.path.exists(os.path.join(d, "greeter.log")) else ""
        errs = [ln for ln in log.splitlines() if "Main.qml" in ln and ("rror" in ln or "not defined" in ln or "nvalid" in ln)]
        row(not errs and os.path.exists(os.path.join(d, "greeter-window.png")),
            f"{os.path.basename(d)}: the greeter drew the theme, no QML error ({len(errs)})" + (": " + errs[0] if errs else ""))
if g2 and g3:
    rect = greeter_rect(g2) or [0, 0, 1920, 1080]
    gx, gy, gw, gh = [int(v) for v in rect]
    wx, wy = gx + (gw - 470) // 2, gy + (gh - 470) // 2
    p2w, p2s = os.path.join(g2, "greeter-window.png"), os.path.join(g2, "greeter-sheet.png")
    p3w, p3s = os.path.join(g3, "greeter-window.png"), os.path.join(g3, "greeter-sheet.png")
    a, b = (np.asarray(Image.open(p).convert("L")).astype(int) for p in (p2w, p2s))
    ys, xs = np.nonzero(np.abs(a - b) > 20)
    sheet = None
    inside = (xs > wx) & (xs < wx + 470) & (ys > wy) & (ys < wy + 470)
    if inside.sum() > 500:
        sx0, sx1, sy0, sy1 = int(xs[inside].min()), int(xs[inside].max()), int(ys[inside].min()), int(ys[inside].max())
        sheet = (sx0, sy0, sx1, sy1)
    row(sheet is not None and 330 < sheet[2] - sheet[0] < 380, f"greeter: Return asked the password in its own box at {sheet}")
    regs_w = [{"name": "pattern (sunk)", "box": [gx + 80, gy + 80, gx + 560, gy + 380], "predicted": SUNK},
              {"name": "window edge", "method": "boundary", "predicted": 0,
               "x_edge": [wx - 14, wy + 200, wx + 14, wy + 260], "y_edge": [wx + 120, wy - 14, wx + 220, wy + 14]},
              {"name": "window texts", "box": [wx + 18, wy + 30, wx + 452, wy + 70], "predicted": 0}]
    res = regions(p3w, p2w, regs_w, "greeter-window")
    for name, v in res.items():
        if isinstance(v, dict):
            row(v.get("pass", False), f"greeter-3d: {name} disparity {v.get('observed')} (predicted {v.get('predicted')}, "
                f"vertical {v.get('vertical_observed')})")
    if sheet:
        sx0, sy0, sx1, sy1 = sheet
        regs_s = [{"name": "password box edge", "method": "boundary", "predicted": -POPPED,
                   "x_edge": [sx0 - 12, sy0 + 40, sx0 + 12, sy0 + 90], "y_edge": [sx0 + 60, sy0 - 12, sx0 + 160, sy0 + 12]},
                  {"name": "password box texts", "box": [sx0 + 14, sy0 + 10, sx0 + 240, sy0 + 60], "predicted": -POPPED},
                  {"name": "window edge under it", "method": "boundary", "predicted": 0,
                   "x_edge": [wx - 14, wy + 380, wx + 14, wy + 440], "y_edge": [wx + 120, wy - 14, wx + 220, wy + 14]}]
        res = regions(p3s, p2s, regs_s, "greeter-sheet")
        for name, v in res.items():
            if isinstance(v, dict):
                row(v.get("pass", False), f"greeter-3d: {name} disparity {v.get('observed')} (predicted {v.get('predicted')}, "
                    f"vertical {v.get('vertical_observed')})")
    mark(p3w, "greeter-3d-window.pns")
    mark(p3s, "greeter-3d-password.pns")
gl = case("greeter-3d-look")
if gl:
    # the same login with the look's own pattern, for looking (not measured: the pattern has nothing to match)
    mark(os.path.join(gl, "greeter-window.png"), "login-3d-look.pns")
    mark(os.path.join(gl, "greeter-sheet.png"), "login-password-3d-look.pns")
    row(os.path.exists(os.path.join(OUT, "login-password-3d-look.pns")), "greeter-3d-look: the login screen over its own pattern, a marked pair")

# ---------------------------------------------------------------- Qt 5 with and without the carry; GTK in the session
d = case("qt5-carry")
if d:
    q = load(os.path.join(d, "qt5.json")) or {}
    mapped = " ".join(q.get("plugins_mapped", []))
    ok = q.get("style", "").lower() == "kvantum" and "KDEPlasmaPlatformTheme5" in mapped
    row(ok, f"qt5-carry: Qt 5 draws {q.get('style')}; platform theme mapped: {'KDEPlasmaPlatformTheme5' in mapped}; "
        f"general font {q.get('general', {}).get('family')} {q.get('general', {}).get('weight')}, "
        f"fixed {q.get('fixed', {}).get('family')}")
    gfont = q.get("general", {}).get("family", "")
    row(gfont in ("Charcoal", "Noto Sans Display"), f"qt5-carry-fonts: the 9's system font reaches Qt 5: {gfont}")
    gs = load(os.path.join(d, "gtk-session.json")) or {}
    for kit in ("gtk3", "gtk4", "gtk2"):
        t = (gs.get(kit) or {}).get("theme")
        row(t == "Kubabbar-Glass-9", f"gtk-session: {kit} in the login loads {t} (sparky-stereo-gtk-sync at login)"
            + (f", overlay scrolling {gs[kit].get('overlay')}" if isinstance(gs.get(kit), dict) and "overlay" in gs[kit] else ""))
d = case("qt5-nocarry")
if d:
    q = load(os.path.join(d, "qt5.json")) or {}
    style = q.get("style", "")
    row(style and style.lower() != "kvantum", f"qt5-nocarry (red control): without the Qt 5 platform theme Qt 5 draws {style}, "
        f"font {q.get('general', {}).get('family')}")

# ---------------------------------------------------------------- texts at 4.5:1 or more (the GTK themes and the login screen)
for accent, A in ACCENTS.items():
    pairs = {"text on face": (TEXT, FACE), "text on view": (TEXT, VIEW), "pressed button": ((255, 255, 255), PRESSED),
             "disabled text": (TEXT_INACTIVE, FACE), "menu highlight": ((255, 255, 255), A["accent"]),
             "selection": (TEXT, A["light"]), "tool tip": (TEXT, TOOLTIP), "login error": ((160, 0, 0), FACE),
             "caps lock note": (TEXT_INACTIVE, FACE), "outline on face": (OUTLINE, FACE)}
    worst = min((contrast(a, b), n) for n, (a, b) in pairs.items())
    row(worst[0] >= 4.5, f"texts-{accent}: lowest {worst[0]:.2f} ({worst[1]}) over {len(pairs)} pairs of the GTK themes and the login screen")

# ---------------------------------------------------------------- the load at each case's start and end
if os.path.exists(os.path.join(OUT, "load.log")):
    for line in open(os.path.join(OUT, "load.log")):
        if " start;" in line or " end;" in line:
            rows.append("INFO " + line.strip())
for r in rows:
    print(r)
print(f"{sum(r.startswith('PASS') for r in rows)} PASS, {sum(r.startswith('FAIL') for r in rows)} FAIL")
