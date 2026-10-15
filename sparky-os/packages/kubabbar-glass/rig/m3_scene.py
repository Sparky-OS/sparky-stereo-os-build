"""Menu bar and dock scenes for one disposable KWin session (run from probe.py inside the lane container only).

  (none)  the gallery: Konsole, Dolphin, Kate (active, so the Global Menu shows its menus) and System Settings, with the panels
  lamp    one window minimised with the Magic Lamp (or Squash) effect, captured frame by frame at a slowed animation
  cost    twelve minimise and restore cycles at normal speed, with the compositor's CPU time read from /proc
"""
import json
import os
import time
from pathlib import Path

import dbus

GALLERY = """var slots = {"org.kde.konsole": [30, 45], "org.kde.dolphin": [810, 45], "org.kde.kate": [30, 440], "kdesystemsettings": [810, 430]};
workspace.windowList().filter(function(w) { return w.normalWindow; }).forEach(function(w) {
    print("window class: " + w.resourceClass + " caption: " + w.caption);
    var s = slots[String(w.resourceClass).toLowerCase()];
    if (s !== undefined) w.frameGeometry = {x: s[0], y: s[1], width: 760, height: 380};
    if (String(w.resourceClass).toLowerCase() === "org.kde.kate") workspace.activeWindow = w;
});
"""
PAIR = """workspace.windowList().filter(function(w) { return w.normalWindow; }).forEach(function(w) {
    var kate = String(w.resourceClass).toLowerCase() === "org.kde.kate";
    w.frameGeometry = kate ? {x: 120, y: 80, width: 900, height: 560} : {x: 560, y: 200, width: 900, height: 560};
    if (kate) workspace.activeWindow = w;
});
"""
PANELS = """var out = [];
panels().forEach(function(p) {
    var ids = p.widgetIds;
    var names = [];
    for (var i = 0; i < ids.length; i++) names.push(p.widgetById(ids[i]).type);
    out.push({location: p.location, height: p.height, opacity: p.opacity, floating: p.floating, lengthMode: p.lengthMode, alignment: p.alignment, hiding: p.hiding, widgets: names});
});
print(JSON.stringify(out));
"""


COUNTER = [0]


def run_script(bus, out, name, source):
    COUNTER[0] += 1
    name = "%s-%d" % (name, COUNTER[0])
    path = out / (name + ".js")
    path.write_text(source)
    scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting"), "org.kde.kwin.Scripting")
    ident = scripting.loadScript(str(path), name, signature="ss")
    dbus.Interface(bus.get_object("org.kde.KWin", f"/Scripting/Script{ident}"), "org.kde.kwin.Script").run()


def cpu_ticks(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return int(fields[11]) + int(fields[12])


def show(bus, plasma, root, home, out, env, scene, launch, gate, capture, case, kwin_pid):
    wallpaper = (root / "share/wallpapers/kubabbar-glass/contents/images/pattern.svg").as_uri()
    plasma.evaluateScript('desktops().forEach(function(d) { d.wallpaperPlugin = "org.kde.image"; d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"]; d.writeConfig("Image", ' + json.dumps(wallpaper) + '); });')
    (home / "Documents/Readme.txt").write_text("Kubabbar Glass\nMenu bar and dock.\n")
    launch("dolphin", ["/usr/bin/dolphin", "--new-window", str(home / "Documents")])
    launch("kate", ["/usr/bin/kate", "--new", str(home / "Documents/Readme.txt")])
    if not scene:
        launch("konsole", ["/usr/bin/konsole", "--separate", "-e", "/bin/sh", "-c", "printf 'Kubabbar Glass: menu bar and dock\\n'; sleep 300"])
        launch("settings", ["/usr/bin/systemsettings"])
    time.sleep(24)
    run_script(bus, out, "layout", GALLERY if not scene else PAIR)
    time.sleep(8)
    try:
        info = str(plasma.evaluateScript(PANELS))
    except Exception as error:
        info = "evaluateScript failed: %s" % error
    (out / "panels.json").write_text(info + "\n")
    (out / "scripting-api.txt").write_text(str(plasma.evaluateScript('print("runCommand: " + typeof runCommand); print("userDataPath: " + typeof userDataPath);')) + "\n")
    if scene == "live":
        live(bus, out, env, gate)
    elif scene == "lamp":
        lamp(bus, out, env, gate, capture)
    elif scene == "cost":
        cost(bus, out, env, kwin_pid, case)
    else:
        gate(bus, out)
        capture(bus, out / "desktop.png")


def loaded(bus):
    info = str(dbus.Interface(bus.get_object("org.kde.KWin", "/KWin"), "org.kde.KWin").supportInformation())
    return info.split("Loaded Effects:")[1].split("Currently Active Effects:")[0].split()


def live(bus, out, env, gate):
    """The session starts with Squash; the layout writes kwinrc for Magic Lamp; then the helper switches the running KWin."""
    import subprocess
    lines = ["after the layout wrote kwinrc: magiclamp loaded=%s squash loaded=%s" % ("magiclamp" in loaded(bus), "squash" in loaded(bus))]
    for effect in ("magiclamp", "squash", "magiclamp"):
        subprocess.run(["kubabbar-glass-minimize", effect], env=env, check=True, capture_output=True)
        time.sleep(4)
        lines.append("after kubabbar-glass-minimize %s: magiclamp loaded=%s squash loaded=%s" % (effect, "magiclamp" in loaded(bus), "squash" in loaded(bus)))
    (out / "live.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


def lamp(bus, out, env, gate, capture):
    gate(bus, out)
    capture(bus, out / "before.png")
    t0 = time.monotonic()
    run_script(bus, out, "minimise", """workspace.windowList().forEach(function(w) { if (String(w.resourceClass).toLowerCase() === "org.kde.kate") w.minimized = true; });""")
    times = []
    for i in range(int(env.get("CLASSIC_FRAMES", "10"))):
        capture(bus, out / ("lamp-%02d.png" % i))
        times.append(round(time.monotonic() - t0, 2))
    (out / "lamp-times.json").write_text(json.dumps({"seconds_after_minimise": times, "animation_factor": env.get("CLASSIC_ANIM"), "effect": env.get("CLASSIC_EFFECT")}) + "\n")
    time.sleep(2)
    capture(bus, out / "after.png")


def cost(bus, out, env, kwin_pid, case):
    cycles = int(env.get("CLASSIC_CYCLES", "12"))
    hz = os.sysconf("SC_CLK_TCK")
    effect = env.get("CLASSIC_EFFECT")
    span = cycles * 3.0
    a = cpu_ticks(kwin_pid)
    time.sleep(span)
    idle = cpu_ticks(kwin_pid) - a
    a = cpu_ticks(kwin_pid)
    for _ in range(cycles):
        run_script(bus, out, "min", """workspace.windowList().forEach(function(w) { if (String(w.resourceClass).toLowerCase() === "org.kde.kate") w.minimized = true; });""")
        time.sleep(1.5)
        run_script(bus, out, "restore", """workspace.windowList().forEach(function(w) { if (String(w.resourceClass).toLowerCase() === "org.kde.kate") w.minimized = false; });""")
        time.sleep(1.5)
    busy = cpu_ticks(kwin_pid) - a
    result = {"effect": effect, "cycles": cycles, "seconds_each_window": span, "clock_ticks_per_second": hz, "kwin_cpu_idle_ms": round(idle * 1000 / hz), "kwin_cpu_cycles_ms": round(busy * 1000 / hz),
              "extra_ms_per_cycle": round((busy - idle) * 1000 / hz / cycles, 1)}
    (out / "cost.json").write_text(json.dumps(result, indent=2) + "\n")
    print(result)
