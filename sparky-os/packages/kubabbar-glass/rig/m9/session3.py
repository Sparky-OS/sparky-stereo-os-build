#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""session3.py STEP: milestone 3's steps inside a real login (rig/m9/probe-m3.sh), with the session's own environment
(plasmashell's), results in $CASE. Shares session2.py's helpers.
  bars            a GTK 3 and a GTK 4 program with a scrolled list (bars.py), on Wayland, left alone with the pointer at
                  the screen's corner: what GTK resolved (overlay scrolling, the bar's classes and opacity) into
                  bars-gtk3.json and bars-gtk4.json, a capture with both on screen (bars.png), and the settings the sync
                  wrote (bars-settings.json: both settings.ini files, dconf's value, the sync's record, the portal)
  greeter-family  SDDM's greeter in test mode with Kubabbar Glass's own theme (row 945), a Wayland window of the session:
                  its log (greeter-family.log) and a capture (greeter-family.png)
  dock            every launcher of the desktop's task managers, and whether its desktop entry is on the system (dock.json)"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import session2  # noqa: E402
from session2 import CASE, FAKEINPUT, M9, evaluate, kwin_windows, session_env, shot  # noqa: E402


def bars():
    env = dict(session_env(), GDK_BACKEND="wayland")
    # the pointer at the screen's corner, away from every bar, before the programs start
    subprocess.run([FAKEINPUT, "m:1910,10", "s:300"], env=env, capture_output=True, text=True)
    procs = []
    for kit in ("3", "4"):
        out = os.path.join(CASE, f"bars-gtk{kit}.json")
        procs.append(subprocess.Popen(["python3", f"{M9}/bars.py", kit, out, "5"], env=env, stdout=subprocess.DEVNULL,
                                      stderr=open(out + ".log", "w")))
    for _ in range(150):
        if all(os.path.exists(os.path.join(CASE, f"bars-gtk{k}.json")) for k in ("3", "4")):
            break
        time.sleep(0.1)
    time.sleep(0.5)
    json.dump(kwin_windows(), open(os.path.join(CASE, "bars-windows.json"), "w"), indent=1)
    shot("bars")
    config = env.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    state = env.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
    report = {}
    for f in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini"):
        path = os.path.join(config, f)
        report[f] = open(path).read() if os.path.exists(path) else None
    record = os.path.join(state, "sparky-stereo-gtk/overlay-scrolling.written")
    report["record"] = open(record).read() if os.path.exists(record) else None
    r = subprocess.run(["dconf", "read", "/org/gnome/desktop/interface/overlay-scrolling"], env=env, capture_output=True,
                       text=True)
    report["dconf"] = r.stdout.strip() if r.returncode == 0 else f"dconf exit {r.returncode}: {r.stderr.strip()}"
    names = session2.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames",
                          reply="(as)")[0]
    report["portal_on_bus"] = "org.freedesktop.portal.Desktop" in names
    report["portal_backends_on_bus"] = sorted(n for n in names if n.startswith("org.freedesktop.impl.portal"))
    json.dump(report, open(os.path.join(CASE, "bars-settings.json"), "w"), indent=1)
    print("bars", json.dumps(report)[:600])
    for p in procs:
        p.terminate()
        p.wait(timeout=10)


def greeter_family():
    env = dict(session_env(), QT_QPA_PLATFORM="wayland", LANG=os.environ.get("GREETER_LANG", "C.UTF-8"))
    env["LC_ALL"] = env["LANG"]
    log = open(os.path.join(CASE, "greeter-family.log"), "w")
    g = subprocess.Popen(["sddm-greeter-qt6", "--test-mode", "--theme", "/usr/share/sddm/themes/kubabbar-glass"],
                         env=env, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(7)
    json.dump(kwin_windows(), open(os.path.join(CASE, "greeter-family-windows.json"), "w"), indent=1)
    shot("greeter-family")
    g.terminate()
    try:
        g.wait(timeout=10)
    except subprocess.TimeoutExpired:
        g.kill()
    log.close()


DOCK_JS = """var out = [];
var ps = panels();
for (var i = 0; i < ps.length; i++) {
  var ws = ps[i].widgets();
  for (var j = 0; j < ws.length; j++) {
    var w = ws[j];
    if (w.type.indexOf("tasks") < 0) continue;
    w.currentConfigGroup = ["General"];
    out.push({panel: i, applet: w.type, launchers: w.readConfig("launchers", "")});
  }
}
print(JSON.stringify(out));"""


def dock():
    raw = evaluate(DOCK_JS).strip().splitlines()[-1]
    data = json.loads(raw)
    dirs = ["/usr/share/applications", "/usr/local/share/applications"]
    for entry in data:
        launchers = entry["launchers"]
        if isinstance(launchers, str):
            launchers = [s for s in launchers.split(",") if s]
        entry["launchers"] = launchers
        entry["present"] = {l: any(os.path.exists(os.path.join(d, l.split(":", 1)[-1])) for d in dirs) for l in launchers}
    json.dump(data, open(os.path.join(CASE, "dock.json"), "w"), indent=1)
    print("dock", json.dumps(data)[:800])


if __name__ == "__main__":
    {"bars": bars, "greeter-family": greeter_family, "dock": dock}[sys.argv[1]]()
