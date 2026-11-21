#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""kwin-script.py KWINLOG 'JS': run JS (KWin scripting API, workspace.*) once in the running KWin, from the rig's D-Bus session."""
import os, sys, time
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
tag = "K265%d" % int(time.monotonic() * 1000)
js = os.path.join(os.environ["XDG_RUNTIME_DIR"], tag + ".js")
open(js, "w").write(sys.argv[2])
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
sid = bus.call_sync("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "loadScript", GLib.Variant("(ss)", (js, tag)), GLib.VariantType("(i)"), Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
for path in ("/Scripting/Script%d" % sid, "/%d" % sid):
    try:
        bus.call_sync("org.kde.KWin", path, "org.kde.kwin.Script", "run", None, None, Gio.DBusCallFlags.NONE, 5000, None)
        break
    except GLib.Error:
        pass
time.sleep(0.5)
bus.call_sync("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "unloadScript", GLib.Variant("(s)", (tag,)), GLib.VariantType("(b)"), Gio.DBusCallFlags.NONE, 5000, None)
os.unlink(js)
