#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""session2.py STEP: milestone 2's steps inside a real login (rig/m9/probe-m2.sh), with the session's own environment
(plasmashell's), geometry from KWin and Plasma's scripting, results in $CASE.
  panels NAME   the desktop's panels (edge, height, floating, opacity, applets), into NAME.json
  keep          the person's own panels kept: Kubabbar Glass 9's menu bar look applied by Plasma's own tool without the
                layout (panels-after-apply.json, as before), then with it (panels-after-reset.json, the menu bar layout)
  greeter       SDDM's greeter in test mode with the 9's theme, a Wayland window of the session: a capture, then Return
                pressed through KWin's fake input, which asks the password in its box, and a capture again
  qt5           a Qt 5 program's style, platform theme and fonts as it resolves them (qt5.json)
  gtk           the GTK theme and overlay scrolling each toolkit loads in the session: GTK 3 and 4 on Wayland, GTK 2 on
                Xwayland (gtk-session.json)"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, "/rig-scripts")
from capture import capture  # noqa: E402
from gi.repository import Gio, GLib  # noqa: E402
from PIL import Image  # noqa: E402

CASE = os.environ["CASE"]
M9 = os.environ.get("M9", "/m9")
FAKEINPUT = os.environ.get("FAKEINPUT", "/fi/fakeinput")
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(dest, path, iface, method, args=None, sig=None, reply="()", timeout=30000):
    params = GLib.Variant(sig, args) if sig else None
    return bus.call_sync(dest, path, iface, method, params, GLib.VariantType(reply), Gio.DBusCallFlags.NONE, timeout,
                         None).unpack()


def evaluate(js):
    return call("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", (js,), "(s)", "(s)")[0]


def shot(name):
    info, px = capture("CaptureScreen", ("Virtual-0",))
    Image.fromarray(px).save(os.path.join(CASE, name + ".png"))
    json.dump({k: (v if isinstance(v, (int, float, str, bool)) else str(v)) for k, v in info.items()},
              open(os.path.join(CASE, name + ".json"), "w"))


def session_env():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            if open(f"/proc/{pid}/comm").read().strip() == "plasmashell":
                raw = open(f"/proc/{pid}/environ", "rb").read().split(b"\0")
                return dict(kv.decode(errors="replace").split("=", 1) for kv in raw if b"=" in kv)
        except OSError:
            continue
    sys.exit("no plasmashell to take the session's environment from")


PANELS_JS = """var out = [];
var ps = panels();
for (var i = 0; i < ps.length; i++) {
  var p = ps[i]; var ws = p.widgets(); var names = [];
  for (var j = 0; j < ws.length; j++) names.push(ws[j].type);
  out.push({location: p.location, height: p.height, floating: p.floating, opacity: p.opacity, hiding: p.hiding,
            alignment: p.alignment, lengthMode: p.lengthMode, applets: names});
}
print(JSON.stringify(out));"""


def panels(name):
    raw = evaluate(PANELS_JS).strip().splitlines()[-1]
    data = json.loads(raw)
    json.dump(data, open(os.path.join(CASE, name + ".json"), "w"), indent=1)
    print(name, json.dumps(data))
    return data


def keep():
    env = session_env()
    before = panels("panels-before")
    log = open(os.path.join(CASE, "apply.log"), "w")
    for name, extra in (("apply", []), ("reset", ["--resetLayout"])):
        r = subprocess.run(["plasma-apply-lookandfeel", "-a", "kubabbar-glass-9-menubar", *extra], env=env,
                           capture_output=True, text=True)
        log.write(f"== plasma-apply-lookandfeel -a kubabbar-glass-9-menubar {' '.join(extra)}: exit {r.returncode}\n"
                  f"{r.stdout}{r.stderr}\n")
        time.sleep(6)
        panels(f"panels-after-{name}")
        shot(f"desktop-after-{name}")
    log.close()
    json.dump({"before": before}, open(os.path.join(CASE, "keep-done.json"), "w"))


def kwin_windows():
    out = subprocess.run(["python3", "/rig-scripts/kwin_windows.py", os.path.join(CASE, "session.log")], capture_output=True, text=True)
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {"error": out.stdout[-400:] + out.stderr[-400:]}


def greeter():
    env = dict(session_env(), QT_QPA_PLATFORM="wayland", LANG=os.environ.get("GREETER_LANG", "C.UTF-8"))
    env["LC_ALL"] = env["LANG"]
    log = open(os.path.join(CASE, "greeter.log"), "w")
    g = subprocess.Popen(["sddm-greeter-qt6", "--test-mode", "--theme", "/usr/share/sddm/themes/kubabbar-glass-9"],
                         env=env, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(7)
    json.dump(kwin_windows(), open(os.path.join(CASE, "greeter-windows.json"), "w"), indent=1)
    shot("greeter-window")
    # one fake input client for the whole case (skill stereo-proof-rig, input-delivery.md): the pointer into the
    # greeter's window, then Return, which asks the password of the chosen person in its own box
    fi = subprocess.run([FAKEINPUT, "m:960,300", "s:400", "b:272", "s:600", "k:28", "s:2500"], env=env,
                        capture_output=True, text=True)
    open(os.path.join(CASE, "fakeinput.log"), "w").write(f"exit {fi.returncode}\n{fi.stdout}{fi.stderr}")
    shot("greeter-sheet")
    g.terminate()
    try:
        g.wait(timeout=10)
    except subprocess.TimeoutExpired:
        g.kill()
    log.close()


QT5_PROBE = r"""
import json, sys
from PyQt5.QtWidgets import QApplication, QMenu, QToolButton
from PyQt5.QtGui import QFontDatabase, QFontInfo
app = QApplication(sys.argv[:1])
def font(f):
    i = QFontInfo(f)
    return {"asked": f.toString(), "family": i.family(), "weight": i.weight(), "pointSize": i.pointSize()}
out = {"style": app.style().objectName(), "platformTheme": app.platformName(),
       "general": font(app.font()), "menu": font(app.font(QMenu())), "toolButton": font(app.font(QToolButton())),
       "fixed": font(QFontDatabase.systemFont(QFontDatabase.FixedFont))}
from PyQt5.QtGui import QGuiApplication
out["theme"] = __import__("os").environ.get("QT_QPA_PLATFORMTHEME", "")
print(json.dumps(out))
"""


def qt5():
    env = dict(session_env(), QT_QPA_PLATFORM="wayland")
    r = subprocess.run(["python3", "-c", QT5_PROBE], env=env, capture_output=True, text=True, timeout=60)
    maps = subprocess.run(["sh", "-c", "python3 -c 'import time; from PyQt5.QtWidgets import QApplication; a=QApplication([]); "
                           "import os; print(open(\"/proc/self/maps\").read())' | grep -o -E '[^ ]*(platformthemes|styles)/[^ ]*\\.so' | sort -u"],
                          env=env, capture_output=True, text=True, timeout=60)
    report = {"probe": r.stdout.strip(), "log": r.stderr[-1500:], "plugins_mapped": maps.stdout.split()}
    try:
        report.update(json.loads(r.stdout.strip().splitlines()[-1]))
    except (ValueError, IndexError):
        pass
    json.dump(report, open(os.path.join(CASE, "qt5.json"), "w"), indent=1)
    print("qt5", json.dumps(report)[:800])


def gtk():
    env = session_env()
    report = {}
    for kit, cmd, extra in (("gtk3", ["python3", f"{M9}/gallery_gtk3.py"], {"GDK_BACKEND": "wayland"}),
                            ("gtk4", ["python3", f"{M9}/gallery_gtk4.py"], {"GDK_BACKEND": "wayland"}),
                            ("gtk2", [os.environ.get("GTK2_GALLERY", "/bin/gallery-gtk2")], {})):
        out = os.path.join(CASE, f"gtk-session-{kit}.json")
        e = dict(env, **extra)
        p = subprocess.Popen(cmd + [out], env=e, stdout=subprocess.DEVNULL, stderr=open(out + ".log", "w"))
        for _ in range(150):
            if os.path.exists(out) and os.path.getsize(out):
                break
            time.sleep(0.1)
        time.sleep(0.5)
        try:
            report[kit] = json.load(open(out))
        except (OSError, ValueError):
            report[kit] = {"error": "no report"}
        p.terminate()
        p.wait(timeout=10)
    config = env.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    for f in ("gtk-3.0/settings.ini", "gtk-4.0/settings.ini", "xsettingsd/xsettingsd.conf"):
        path = os.path.join(config, f)
        report[f] = open(path).read() if os.path.exists(path) else None
    path = os.path.expanduser("~/.gtkrc-2.0")
    report[".gtkrc-2.0"] = open(path).read() if os.path.exists(path) else None
    json.dump(report, open(os.path.join(CASE, "gtk-session.json"), "w"), indent=1)
    print("gtk", json.dumps({k: (v.get("theme") if isinstance(v, dict) else v) for k, v in report.items()})[:800])


if __name__ == "__main__":
    step = sys.argv[1]
    if step == "panels":
        panels(sys.argv[2])
    else:
        {"keep": keep, "greeter": greeter, "qt5": qt5, "gtk": gtk}[step]()
