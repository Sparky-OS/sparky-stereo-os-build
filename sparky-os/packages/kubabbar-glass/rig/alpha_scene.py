"""Real Plasma applet and panel popup over a known solid wallpaper."""
import json
import subprocess
import time
from pathlib import Path


def install(root, home):
    target = home / ".local/share/plasma/plasmoids"
    target.mkdir(parents=True, exist_ok=True)
    (target / "org.sparkystereo.alpha-probe").symlink_to(root / "rig/alpha-applet", target_is_directory=True)


def show(plasma, root, home, out, env, case):
    for _ in range(100):
        ready = str(plasma.evaluateScript('if (panels().length && desktops().length) print("PANEL_READY");'))
        if "PANEL_READY" in ready:
            break
        time.sleep(.2)
    else:
        raise RuntimeError("Plasma's initial desktop and panel did not finish loading")
    theme, background, mode = case.removeprefix("alpha-").split("-")
    shade = "#000000" if background == "black" else "#ffffff"
    wallpaper = home / "wallpaper.svg"
    wallpaper.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1000"><rect width="1600" height="1000" fill="{shade}"/></svg>')
    script = '''
desktops().forEach(function(d) {
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", WALLPAPER);
    d.widgets().forEach(function(w) { w.remove(); });
    var w = d.addWidget("org.sparkystereo.alpha-probe");
    w.geometry = {x: 130, y: 180, width: 400, height: 300};
});
var p = panels()[0] || new Panel();
p.widgets().forEach(function(w) { w.remove(); });
p.screen = 0;
p.location = "bottom";
p.height = 48;
p.addWidget("org.sparkystereo.alpha-probe");
'''.replace("WALLPAPER", json.dumps(wallpaper.as_uri()))
    (out / "plasma-layout.js").write_text(script)
    plasma.evaluateScript(script)
    subprocess.run(["kscreen-doctor", "--help"], env=env, stdout=(out / "kscreen-help.txt").open("w"), stderr=subprocess.STDOUT)
    subprocess.run(["kscreen-doctor", "-o"], env=env, stdout=(out / "outputs.txt").open("w"), stderr=subprocess.STDOUT)
    time.sleep(10)
