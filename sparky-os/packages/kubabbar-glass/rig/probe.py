#!/usr/bin/env python3
"""One disposable headless KWin session. Run inside the lane container only."""
import configparser
import json
import hashlib
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path

import dbus
from dbus.types import UnixFd
from PIL import Image
import alpha_scene
import window_probe

ROOT = Path(__file__).resolve().parents[1]
CASE = os.environ.get("CLASSIC_CASE", "2d")
M2 = CASE.startswith("m2-")
M2_STYLE, M2_LOOK, M2_MODE = CASE.split("-")[1:4] if M2 else (None, None, None)
SCENE = os.environ.get("CLASSIC_SCENE", "")
HOME_DIR = ROOT / "rig/home" / (CASE + ("-" + SCENE if SCENE else ""))
OUT = ROOT / "evidence" / (CASE + ("-" + SCENE if SCENE else ""))
RUNTIME = ROOT.parent / "run" / hashlib.sha256(CASE.encode()).hexdigest()[:8]


def gate(bus, out, name="support"):
    info = str(dbus.Interface(bus.get_object("org.kde.KWin", "/KWin"), "org.kde.KWin").supportInformation())
    (out / (name + ".txt")).write_text(info)
    assert "Compositing Type: OpenGL" in info, "QPainter is not a valid proof backend"
    loaded = info.split("Loaded Effects:")[1].split("Currently Active Effects:")[0].splitlines()
    assert "translucency" in loaded, "Translucency must load before capture"
    assert "blur" not in loaded and "contrast" not in loaded


def capture(bus, path):
    read_fd, write_fd = os.pipe()
    chunks = []

    def consume():
        with os.fdopen(read_fd, "rb") as stream:
            while data := stream.read(1024 * 1024):
                chunks.append(data)

    reader = threading.Thread(target=consume, daemon=True)
    reader.start()
    sender_fd = UnixFd(write_fd)
    try:
        obj = bus.get_object("org.kde.KWin", "/org/kde/KWin/ScreenShot2")
        result = obj.CaptureArea(0, 0, 1600, 1000, dbus.Dictionary({}, signature="sv"), sender_fd, dbus_interface="org.kde.KWin.ScreenShot2", timeout=30)
    finally:
        os.close(write_fd)
        os.close(sender_fd.take())
    reader.join(30)
    if reader.is_alive():
        raise RuntimeError("Screenshot pipe did not complete")
    metadata = {str(k): int(v) if isinstance(v, (dbus.UInt32, dbus.Int32)) else bool(v) if isinstance(v, dbus.Boolean) else float(v) if isinstance(v, dbus.Double) else str(v) for k, v in result.items()}
    path.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n")
    raw = b"".join(chunks)
    width, height, stride = int(result["width"]), int(result["height"]), int(result["stride"])
    assert len(raw) == stride * height, (len(raw), stride, height)
    assert int(result["format"]) in (4, 5, 6), metadata
    image = Image.frombytes("RGBA", (width, height), raw, "raw", "BGRA", stride).convert("RGB")
    image.save(path)
    if CASE.endswith("-stereo"):
        assert metadata.get("stereo") is True and width == 3200, metadata
        prefix = "" if path.stem == "desktop" else path.stem + "-"
        image.crop((0, 0, width // 2, height)).save(path.with_name(prefix + "LEFT.png"))
        image.crop((width // 2, 0, width, height)).save(path.with_name(prefix + "RIGHT.png"))


def m2_setup(home):
    if SCENE == "trash-full":
        files, info = home / ".local/share/Trash/files", home / ".local/share/Trash/info"
        files.mkdir(parents=True, exist_ok=True)
        info.mkdir(parents=True, exist_ok=True)
        (files / "old-notes.txt").write_text("thrown away\n")
        (info / "old-notes.txt.trashinfo").write_text("[Trash Info]\nPath=/old-notes.txt\nDeletionDate=2026-10-14T20:00:00\n")
        (home / ".config/trashrc").write_text("[Status]\nEmpty=false\n")
    if M2_STYLE == "kvantum" or SCENE == "qt5-kvantum":
        kv = home / ".config/Kvantum"
        kv.mkdir(parents=True, exist_ok=True)
        (kv / "kvantum.kvconfig").write_text("[General]\ntheme=%s\n" % os.environ.get("CLASSIC_KVANTUM", "KubabbarGlass"))
        source = ROOT / "share/Kvantum/KubabbarGlass"
        if source.exists():
            (kv / "KubabbarGlass").symlink_to(source, target_is_directory=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if HOME_DIR.exists():
        shutil.rmtree(HOME_DIR)
    HOME_DIR.mkdir(parents=True)
    for directory in (".config", ".cache", ".local/share", "runtime", "Documents"):
        (HOME_DIR / directory).mkdir(parents=True, exist_ok=True)
    (HOME_DIR / "runtime").chmod(0o700)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    RUNTIME.chmod(0o700)
    (HOME_DIR / "Documents/Readme.txt").write_text("Kubabbar Glass\nOriginal artwork, shared desktop, two eyes.\n")
    for directory in (ROOT / "share").iterdir():
        if directory.name == "plasma":
            (HOME_DIR / ".local/share/plasma").mkdir()
            (HOME_DIR / ".local/share/plasma/desktoptheme").symlink_to(directory / "desktoptheme", target_is_directory=True)
        elif directory.name == "kwin":
            decorations = HOME_DIR / ".local/share/kwin/decorations"
            decorations.mkdir(parents=True)
            for theme in (directory / "decorations").iterdir():
                (decorations / theme.name).symlink_to(theme, target_is_directory=True)
        else:
            (HOME_DIR / ".local/share" / directory.name).symlink_to(directory, target_is_directory=True)
    alpha_scene.install(ROOT, HOME_DIR)
    if CASE == "platform-stereo":
        decorations = HOME_DIR / ".local/share/kwin/decorations"
        decorations.mkdir(parents=True, exist_ok=True)
        (decorations / "org.sparkystereo.shade-probe").symlink_to(ROOT / "rig/shade-decoration", target_is_directory=True)
    shutil.copy(ROOT / "config/kwinrc", HOME_DIR / ".config/kwinrc")
    if CASE == "platform-stereo":
        path = HOME_DIR / ".config/kwinrc"
        path.write_text(path.read_text().replace("kubabbar-glass", "org.sparkystereo.shade-probe"))
    if CASE.endswith("-stereo"):
        outputs = [{"connectorName": f"Virtual-{i}", "uuid": f"classic-eye-{i}",
                    "stereoPartner": f"classic-eye-{1-i}", "stereoPairMode": "DualProjection",
                    "stereoPairRole": role, "stereoPairReflection": "None",
                    "mode": {"width": 1600, "height": 1000, "refreshRate": 60000, "flags": 1},
                    "scale": 1, "transform": "Normal"} for i, role in enumerate(("Left", "Right"))]
        output_config = [{"name": "outputs", "data": outputs}, {"name": "setups", "data": [{"lidClosed": False, "outputs": [{"enabled": True, "outputIndex": i, "position": {"x": 0, "y": 0}, "priority": i} for i in range(2)]}]}]
        (HOME_DIR / ".config/kwinoutputconfig.json").write_text(json.dumps(output_config))
    config = configparser.ConfigParser()
    config.optionxform = str
    config.read(ROOT / "share/color-schemes/kubabbar-glass.colors")
    if CASE.startswith("windows-oxygen-") or M2_LOOK == "oxygen":
        config.clear()
        assert config.read("/usr/share/color-schemes/OxygenDark.colors"), "OxygenDark palette is required"
        kwin_config = configparser.ConfigParser()
        kwin_config.optionxform = str
        kwin_config.read(HOME_DIR / ".config/kwinrc")
        kwin_config["org.kde.kdecoration2"] = {"library": "org.kde.oxygen"}
        with (HOME_DIR / ".config/kwinrc").open("w") as stream:
            kwin_config.write(stream)
    if M2_LOOK == "oxygen":
        config["General"]["ColorScheme"] = "OxygenDark"
    config["General"]["font"] = "DejaVu Sans,10,-1,5,50,0,0,0,0,0"
    if "KDE" not in config:
        config["KDE"] = {}
    config["KDE"]["widgetStyle"] = {"breeze": "Breeze", "fusion": "Fusion", "kvantum": "kvantum", "oxygenqt": "Oxygen"}[M2_STYLE] if M2 else "Fusion"
    config["Icons"] = {"Theme": "kubabbar-glass-stereo" if SCENE.startswith("trash") else "oxygen"}
    with (HOME_DIR / ".config/kdeglobals").open("w") as f:
        config.write(f)
    style = "sparky-stereo-oxygen" if ("oxygen" in CASE and not M2) or M2_LOOK == "oxygen" else "kubabbar-glass"
    if M2:
        m2_setup(HOME_DIR)
    (HOME_DIR / ".config/plasmarc").write_text(f"[Theme]\nname={style}\n")
    (HOME_DIR / ".config/katerc").write_text("[project]\nautorepository=\nautoCMake=false\n")
    env = dict(os.environ, HOME=str(HOME_DIR), XDG_CONFIG_HOME=str(HOME_DIR / ".config"),
               XDG_DATA_HOME=str(HOME_DIR / ".local/share"), XDG_CACHE_HOME=str(HOME_DIR / ".cache"),
               XDG_RUNTIME_DIR=str(RUNTIME), TMPDIR=str(RUNTIME), QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY="kubabbar-glass",
               XDG_SESSION_TYPE="wayland", XDG_CURRENT_DESKTOP="KDE", LANG="C.UTF-8",
               KWIN_COMPOSE="O2", QT_LOGGING_RULES="kwin_scripting*=true", KWIN_SCREENSHOT_NO_PERMISSION_CHECKS="1", QT_QUICK_BACKEND="software")
    env.pop("DISPLAY", None)
    env.pop("LIBGL_ALWAYS_SOFTWARE", None)
    env.pop("MESA_LOADER_DRIVER_OVERRIDE", None)
    env.pop("GALLIUM_DRIVER", None)
    processes, logs = [], []

    def launch(name, command, extra=None):
        log = (OUT / f"{name}.log").open("w")
        logs.append(log)
        p = subprocess.Popen(command, env=dict(env, **(extra or {})), stdout=log, stderr=subprocess.STDOUT)
        processes.append(p)
        return p

    try:
        kwin = launch("kwin", [str(ROOT / "rig/bin/kwin_wayland"), "--virtual", "--output-count", "2" if CASE.endswith("-stereo") else "1", "--width", "1600", "--height", "1000", "--socket", "kubabbar-glass", "--no-lockscreen", "--no-global-shortcuts", "--no-kactivities"])
        bus = dbus.SessionBus()
        dbus.Interface(bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus"), "org.freedesktop.DBus").UpdateActivationEnvironment(dbus.Dictionary({k: env[k] for k in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "QT_QPA_PLATFORM", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP", "LANG")}, signature="ss"))
        for _ in range(100):
            if kwin.poll() is not None:
                raise RuntimeError(f"KWin exited {kwin.returncode}")
            if bus.name_has_owner("org.kde.KWin") and (RUNTIME / "kubabbar-glass").exists():
                break
            time.sleep(.2)
        else:
            raise RuntimeError("KWin did not become ready")
        if M2:
            launch("kded", ["/usr/bin/kded6"])
        launch("plasma", ["/usr/bin/plasmashell"])
        time.sleep(5)
        plasma = dbus.Interface(bus.get_object("org.kde.plasmashell", "/PlasmaShell"), "org.kde.PlasmaShell")
        if CASE.startswith("windows-") or CASE == "platform-stereo":
            window_probe.show(bus, plasma, ROOT, HOME_DIR, OUT, "windows-classic-black-stereo" if CASE == "platform-stereo" else CASE, launch, gate, capture)
            return
        if CASE.startswith("alpha-"):
            alpha_scene.show(plasma, ROOT, HOME_DIR, OUT, env, CASE)
            gate(bus, OUT)
            capture(bus, OUT / "desktop.png")
            return
        wallpaper = (ROOT / "share/wallpapers/kubabbar-glass/contents/images/pattern.svg").as_uri()
        plasma.evaluateScript('desktops().forEach(function(d) { d.wallpaperPlugin = "org.kde.image"; d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"]; d.writeConfig("Image", ' + json.dumps(wallpaper) + '); });')
        if M2:
            with (OUT / "gtk-sync.log").open("w") as sync_log:
                subprocess.run([str(ROOT / "bin/sparky-stereo-gtk-sync")], env=env, stdout=sync_log, stderr=subprocess.STDOUT, check=True)
        audit = {"LD_PRELOAD": str(ROOT / "rig/bin/style-audit.so")} if os.environ.get("CLASSIC_AUDIT") else {}
        if SCENE.startswith("qt5"):
            launch("qt5", ["/usr/bin/env", "QT_QPA_PLATFORM=wayland", *(["QT_STYLE_OVERRIDE=" + SCENE.split("-")[1]] if "-" in SCENE else []), "python3", str(ROOT / "rig/m2/qt5_window.py")])
        else:
            launch("dolphin", ["/usr/bin/dolphin", "--new-window", "trash:/" if SCENE else str(HOME_DIR / "Documents")], audit)
        if not SCENE:
            launch("konsole", ["/usr/bin/konsole", "--separate", "-e", "/bin/sh", "-c", "printf 'Kubabbar Glass: terminal\n'; sleep 120"], audit)
        if not SCENE:
            launch("kate", ["/usr/bin/kate", "--new", str(HOME_DIR / "Documents/Readme.txt")], audit)
        if not SCENE:
            launch("settings", ["/usr/bin/systemsettings"], audit)
        if not SCENE:
            launch("gtk", ["/usr/bin/env", "GTK_DEBUG=css", *os.environ.get("CLASSIC_GTK3_ENV", "X=1").split(), "/usr/bin/gtk3-demo", "--run=application"])
        if M2 and not SCENE:
            launch("gtk4", ["/usr/bin/env", "GTK_DEBUG=css", *os.environ.get("CLASSIC_GTK4_ENV", "X=1").split(), "/usr/bin/gtk4-demo"])
        time.sleep(20 if M2 else 10)
        scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting"), "org.kde.kwin.Scripting")
        script_path = OUT / "layout.js"
        script_path.write_text('''var windows = workspace.windowList().filter(function(w) { return w.normalWindow; });
windows.forEach(function(w) { w.frameGeometry = {x: 300, y: 60, width: WIDTH, height: HEIGHT}; });
'''.replace("WIDTH", "520" if SCENE.startswith("qt5") else "1000").replace("HEIGHT", "430" if SCENE.startswith("qt5") else "700") if SCENE else '''var slots = {"gtk3-demo": 0, "org.kde.konsole": 1, "org.kde.dolphin": 2, "org.kde.kate": 3, "systemsettings": 4, "org.kde.systemsettings": 4, "org.gtk.demo4": 5, "gtk4-demo": 5};
var used = {};
var windows = workspace.windowList().filter(function(w) { return w.normalWindow; });
windows.forEach(function(w) {
    var slot = slots[String(w.resourceClass).toLowerCase()];
    if (slot !== undefined) used[slot] = true;
    w.slot = slot;
});
var next = 0;
windows.forEach(function(w) {
    if (w.slot === undefined) { while (used[next]) next++; w.slot = next; used[next] = true; }
    w.frameGeometry = {x: 35 + (w.slot % 3) * 510, y: 55 + Math.floor(w.slot / 3) * 420, width: 500, height: 395};
});
''')
        script_id = scripting.loadScript(str(script_path), "kubabbar-glass-layout", signature="ss")
        dbus.Interface(bus.get_object("org.kde.KWin", f"/Scripting/Script{script_id}"), "org.kde.kwin.Script").run()
        time.sleep(12 if M2 else 3)
        if M2:
            try:
                runner = dbus.Interface(bus.get_object("org.kde.KWin", "/WindowsRunner"), "org.kde.krunner1")
                listing = []
                for query in ("a", "e", "o", "i", "u"):
                    listing += [str(m) for m in runner.Match(query)]
                (OUT / "windows.txt").write_text("\n".join(sorted(set(listing))) + "\n")
            except Exception as error:
                (OUT / "windows.txt").write_text("runner failed: %s\n" % error)
        gate(bus, OUT)
        capture(bus, OUT / "desktop.png")
        (OUT / "processes.txt").write_text("".join("%s exit=%s\n" % (" ".join(map(str, p.args)), p.poll()) for p in processes))
    finally:
        for p in reversed(processes):
            if p.poll() is None:
                p.terminate()
        for p in processes:
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
