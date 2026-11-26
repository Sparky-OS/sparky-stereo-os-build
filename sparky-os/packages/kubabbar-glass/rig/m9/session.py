#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""session.py widget|apps|fonts: steps of Kubabbar Glass 9's probe inside a real login (rig/m9/probe9.sh).
Programs are started with the environment of the session's own plasmashell, so they read the session's configuration
the way a program the person starts does (the probe's shell is not started by Plasma). Geometry comes from KWin and
Plasma's scripting, never from the picture. Writes into $CASE."""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, "/rig-scripts")
import numpy as np  # noqa: E402
from capture import capture  # noqa: E402
from gi.repository import Gio, GLib  # noqa: E402
from PIL import Image  # noqa: E402

CASE = os.environ["CASE"]
PROBE = ["python3", "/rig-scripts/translucency-probe/probe.py"]
M9 = os.environ.get("M9", "/m9")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(dest, path, iface, method, args=None, sig=None, reply="()", timeout=30000):
    params = GLib.Variant(sig, args) if sig else None
    return bus.call_sync(dest, path, iface, method, params, GLib.VariantType(reply), Gio.DBusCallFlags.NONE, timeout,
                         None).unpack()


def evaluate(js):
    return call("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", (js,), "(s)", "(s)")[0]


def kwin(js, name):
    path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), name + ".js")
    open(path, "w").write(js)
    sid = call("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "loadScript", (path, name), "(ss)", "(i)")[0]
    call("org.kde.KWin", f"/Scripting/Script{sid}", "org.kde.kwin.Script", "run")
    time.sleep(0.4)
    call("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "unloadScript", (name,), "(s)", "(b)")


def windows(tag):
    return json.loads(subprocess.run(PROBE + ["windows", tag], capture_output=True, text=True, check=True).stdout)


def shot(name):
    info, px = capture("CaptureScreen", ("Virtual-0",))
    Image.fromarray(px).save(os.path.join(CASE, name + ".png"))
    json.dump({k: (v if isinstance(v, (int, float, str, bool)) else str(v)) for k, v in info.items()},
              open(os.path.join(CASE, name + ".json"), "w"))
    return px


def session_env():
    """The environment of the session's plasmashell (the person's programs get the same from Plasma)."""
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if open(f"/proc/{pid}/comm").read().strip() == "plasmashell":
                raw = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
                env = dict(kv.decode(errors="replace").split("=", 1) for kv in raw if b"=" in kv)
                return env
        except OSError:
            continue
    sys.exit("no plasmashell to take the session's environment from")


def alpha_in(name, box):
    """1 - (white - black)/255 inside box, as the translucency probe's analyze.py reads a surface."""
    x, y, w, h = box
    b = np.asarray(Image.open(os.path.join(CASE, f"{name}-black.png")).convert("RGB")).astype(float)[y:y + h, x:x + w]
    wh = np.asarray(Image.open(os.path.join(CASE, f"{name}-white.png")).convert("RGB")).astype(float)[y:y + h, x:x + w]
    a = (1 - (wh - b) / 255.0).mean(axis=2)
    drawn = (a > 0.03) & (a < 0.97)
    if drawn.sum() < 50:
        return {"box": box, "drawn_pixels": int(drawn.sum())}
    return {"box": box, "drawn_pixels": int(drawn.sum()), "alpha_8bit_median": int(round(float(np.median(a[drawn])) * 255)),
            "alpha_p05": round(float(np.percentile(a[drawn], 5)), 4), "alpha_p95": round(float(np.percentile(a[drawn], 95)), 4)}


def widget():
    """A desktop widget over black and white: its background's level as the screen shows it. Only a widget that draws
    Plasma's standard background counts (System Monitor declares DefaultBackground; Folder View draws it as a widget):
    the desktop clocks draw none, only shadowed text, so a reading counts only when the translucent pixels cover most
    of the box."""
    walls = os.path.join(CASE, "walls")
    results = {}
    for applet in ("org.kde.plasma.systemmonitor", "org.kde.plasma.folder"):
        out = evaluate("var d = desktops()[0]; var w = d.addWidget(%s, 640, 260, 420, 300);"
                       " print(JSON.stringify({id: w.id, x: w.geometry.x, y: w.geometry.y, w: w.geometry.width,"
                       " h: w.geometry.height}));" % json.dumps(applet))
        time.sleep(2.5)
        try:
            g = json.loads(out.strip().splitlines()[-1])
        except (ValueError, IndexError):
            results[applet] = {"error": out}
            continue
        for wall in ("black", "white"):
            subprocess.run(PROBE + ["wall", os.path.join(walls, wall + ".png")], check=True, capture_output=True)
            shot(f"widget-{wall}")
        inset = 12
        box = [int(g["x"]) + inset, int(g["y"]) + inset, int(g["w"]) - 2 * inset, int(g["h"]) - 2 * inset]
        r = dict(alpha_in("widget", box), frame=g)
        r["coverage"] = round(r["drawn_pixels"] / float(box[2] * box[3]), 3)
        results[applet] = r
        evaluate("var d = desktops()[0]; var ws = d.widgets(); for (var i = 0; i < ws.length; i++)"
                 " if (ws[i].id == %d) ws[i].remove();" % g["id"])
        time.sleep(1)
        if r.get("alpha_8bit_median") is not None and r["coverage"] >= 0.5:
            break
    json.dump(results, open(os.path.join(CASE, "widget.json"), "w"), indent=1)
    print("widget", json.dumps(results))


APPS = [("dolphin", ["dolphin", "/usr/share"], (30, 40, 760, 470)),
        ("konsole", ["konsole"], (820, 40, 560, 330)),
        ("systemsettings", ["systemsettings"], (1100, 400, 790, 560)),
        ("kate", ["kate", "/usr/share/doc/sparky-stereo-look-kubabbar-glass-9/README.md"], (60, 540, 700, 420)),
        ("gallery-qt6", ["python3", "/m9/gallery.py", "/dev/null", "--window"], (300, 120, 860, 560)),
        ("gallery-qt5", ["python3", "/m9/gallery.py", "/dev/null", "--window", "--qt5"], (360, 180, 860, 560))]


def apps():
    env = session_env()
    keys = ("XDG_CONFIG_DIRS", "XDG_CURRENT_DESKTOP", "KDE_SESSION_VERSION", "QT_QPA_PLATFORMTHEME", "DISPLAY",
            "WAYLAND_DISPLAY", "LANG")
    json.dump({"session (plasmashell)": {k: env.get(k) for k in keys}, "probe's own shell": {k: os.environ.get(k) for k in keys}},
              open(os.path.join(CASE, "session-env.json"), "w"), indent=1)
    only = os.environ.get("APPS", "").split()
    procs = []
    for name, argv, _ in APPS:
        if only and name not in only:
            continue
        e = dict(env)
        if name == "gallery-qt5":
            e["QT_QPA_PLATFORM"] = "xcb"          # Qt 5 programs reach the session through Xwayland here
        procs.append(subprocess.Popen(argv, env=e, stdout=open(os.path.join(CASE, f"app-{name}.log"), "w"),
                                      stderr=subprocess.STDOUT))
        time.sleep(4)
    time.sleep(6)
    place = []
    for name, argv, (x, y, w, h) in APPS:
        if only and name not in only:
            continue
        key = {"gallery-qt6": "Kubabbar Glass 9 gallery", "gallery-qt5": "Kubabbar Glass 9 gallery"}.get(name)
        place.append((name, key, x, y, w, h))
    js = ["var ws = workspace.stackingOrder; var used = {};"]
    for name, key, x, y, w, h in place:
        if key:
            test = "ws[i].caption == %s && !used[i]" % json.dumps(key)
        else:
            test = "ws[i].resourceClass.indexOf(%s) >= 0 && !used[i]" % json.dumps(name)
        js.append("for (var i = 0; i < ws.length; i++) { if (%s) { used[i] = 1; ws[i].setMaximize(false, false);"
                  " ws[i].frameGeometry = {x: %d, y: %d, width: %d, height: %d}; break; } }" % (test, x, y, w, h))
    kwin("\n".join(js), "m9place")
    time.sleep(2)
    kwin("var ws = workspace.stackingOrder; for (var i = 0; i < ws.length; i++) if (ws[i].resourceClass.indexOf('dolphin') >= 0)"
         " workspace.activeWindow = ws[i];", "m9activate")
    time.sleep(3)
    json.dump(windows("apps"), open(os.path.join(CASE, "win-apps.json"), "w"), indent=1)
    shot("apps")
    print("apps", len(procs), "programs")
    for p in procs:
        p.terminate()


def fonts():
    env = session_env()
    report = {}
    # Each Qt on the session's own platform, as a program started there (Qt 6 on Wayland, Qt 5 through Xwayland), so the
    # platform theme loads as it does for a real program. Qt 6 has no MenuFont or ToolbarFont system font: the menu and
    # tool bar fonts are what the application gives QMenu, QMenuBar and QToolButton (Qt hands the platform theme's tool
    # button font to QToolButton; QToolBar itself takes the general font).
    code6 = ("from PyQt6.QtGui import QFontDatabase, QFontInfo; from PyQt6.QtWidgets import QApplication; import json;"
             "a = QApplication([]); T = QFontDatabase.SystemFont; r = {}\n"
             "w = lambda v: getattr(v, 'value', v)\n"
             "def row(f):\n"
             "    i = QFontInfo(f)\n"
             "    return {'asked': f.family(), 'size': f.pointSizeF(), 'weight': w(f.weight()), 'drawn': i.family(), 'drawn_weight': w(i.weight())}\n"
             "for n in ('GeneralFont', 'FixedFont', 'SmallestReadableFont', 'TitleFont'):\n"
             "    r[n] = row(QFontDatabase.systemFont(getattr(T, n)))\n"
             "for c in ('QMenu', 'QMenuBar', 'QToolButton', 'QToolBar'):\n"
             "    r[c] = row(QApplication.font(c))\n"
             "r['style'] = a.style().name(); r['platform'] = a.platformName(); print(json.dumps(r))")
    out = subprocess.run(["python3", "-c", code6], env=dict(env, QT_QPA_PLATFORM="wayland"), capture_output=True, text=True)
    report["qt6"] = json.loads(out.stdout.strip().splitlines()[-1]) if out.returncode == 0 else {"error": out.stderr[-400:]}
    code5 = ("from PyQt5.QtGui import QFontDatabase, QFontInfo; from PyQt5.QtWidgets import QApplication; import json;"
             "a = QApplication([]); r = {}\n"
             "for n in ('GeneralFont', 'FixedFont', 'SmallestReadableFont', 'TitleFont'):\n"
             "    f = QFontDatabase.systemFont(getattr(QFontDatabase, n)); i = QFontInfo(f)\n"
             "    r[n] = {'asked': f.family(), 'size': f.pointSizeF(), 'weight': f.weight(), 'drawn': i.family()}\n"
             "r['style'] = a.style().objectName(); r['platform'] = a.platformName(); print(json.dumps(r))")
    out = subprocess.run(["python3", "-c", code5], env=dict(env, QT_QPA_PLATFORM="xcb"), capture_output=True, text=True)
    report["qt5"] = json.loads(out.stdout.strip().splitlines()[-1]) if out.returncode == 0 else {"error": out.stderr[-400:]}
    report["fc-match"] = {name: subprocess.run(["fc-match", "-f", "%{family[0]}:%{style[0]}", name], env=env,
                                               capture_output=True, text=True).stdout for name in
                          ("Charcoal", "Chicago", "Geneva", "Monaco", "Charcoal:bold")}
    report["installed-classic"] = {name: subprocess.run(["fc-list", "-q", name], env=env).returncode == 0 for name in
                                   ("Charcoal", "Geneva", "Monaco")}
    cfg = os.path.join(env.get("HOME", ""), ".config")
    for rel in ("kdedefaults/package", "kdedefaults/kubabbar-glass-9-sync.written", "kdedefaults/Kvantum/kvantum.kvconfig"):
        p = os.path.join(cfg, rel)
        report[rel] = open(p).read() if os.path.exists(p) else None
    report["kreadconfig6 font (the session's cascade)"] = subprocess.run(
        ["kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", "font"], env=env, capture_output=True, text=True).stdout.strip()
    json.dump(report, open(os.path.join(CASE, "fonts.json"), "w"), indent=1, ensure_ascii=False)
    print("fonts", json.dumps(report)[:600])


{"widget": widget, "apps": apps, "fonts": fonts}[sys.argv[1]]()
