"""Separate windows and full-screen controls over a known wallpaper."""
import json
import time
import dbus


def script(bus, out, name, source):
    path = out / (name + ".js")
    path.write_text(source)
    scripting = dbus.Interface(bus.get_object("org.kde.KWin", "/Scripting"), "org.kde.kwin.Scripting")
    ident = scripting.loadScript(str(path), name, signature="ss")
    dbus.Interface(bus.get_object("org.kde.KWin", f"/Scripting/Script{ident}"), "org.kde.kwin.Script").run()


def show(bus, plasma, root, home, out, case, launch, gate, capture):
    _, theme, background, mode = case.split("-")
    wallpaper = home / "wallpaper.svg"
    shade = "#000000" if background == "black" else "#ffffff"
    wallpaper.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1000"><rect width="1600" height="1000" fill="{shade}"/></svg>')
    plasma.evaluateScript('desktops().forEach(function(d) { d.wallpaperPlugin="org.kde.image"; d.currentConfigGroup=["Wallpaper","org.kde.image","General"]; d.writeConfig("Image",' + json.dumps(wallpaper.as_uri()) + '); });')
    launch("windows", ["python3", str(root / "rig/window_scene.py")])
    time.sleep(5)
    script(bus, out, "windows-layout", '''
var positions = {"Inactive 91%": [80,80,420,320], "Dialog 91%": [600,80,420,320], "Active opaque": [700,430,600,390]};
workspace.windowList().forEach(function(w) {
    if (!(w.caption in positions)) return;
    var p = positions[w.caption];
    w.frameGeometry = {x:p[0], y:p[1], width:p[2], height:p[3]};
    if (w.caption === "Active opaque") workspace.activeWindow = w;
});
''')
    time.sleep(3)
    gate(bus, out)
    capture(bus, out / "desktop.png")
    if out.name == "platform-stereo":
        script(bus, out, "shade-request", '''workspace.windowList().forEach(function(w) {
    if (w.caption !== "Active opaque") return;
    print("SHADE_BEFORE=" + JSON.stringify({shadeable:w.shadeable, shaded:w.shaded, height:w.frameGeometry.height, slot:typeof workspace.slotWindowShade}));
    w.shaded = true;
    if (typeof workspace.slotWindowShade === "function") workspace.slotWindowShade();
});''')
        time.sleep(2)
        script(bus, out, "shade-state", '''workspace.windowList().forEach(function(w) {
    if (w.caption === "Active opaque") print("SHADE_AFTER=" + JSON.stringify({shadeable:w.shadeable, shaded:w.shaded, height:w.frameGeometry.height}));
});''')
        gate(bus, out, "shade-support")
        capture(bus, out / "shade-request.png")
    (home / "fullscreen-request").touch()
    time.sleep(3)
    script(bus, out, "fullscreen-state", '''workspace.windowList().forEach(function(w) {
    if (w.caption === "Fullscreen opaque") print("FULLSCREEN_CONTROL=" + w.fullScreen);
});''')
    gate(bus, out, "fullscreen-support")
    capture(bus, out / "fullscreen.png")
