#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""bars.py 3|4 OUT.json [SECONDS]: a person's GTK 3 or GTK 4 program with a scrolled list (row 147, milestone 3). After it
has been left alone for SECONDS (default 5; the pointer elsewhere), it writes the overlay scrolling GTK resolved and the
state of its vertical scroll bar: an overlay indicator carries the class overlay-indicator and fades to opacity 0 when
idle (gtkscrolledwindow.c, indicator_set_fade), a permanent bar has neither; and, in GTK 4, the steppers' sizes."""
import json
import sys

import gi

kit, out = sys.argv[1], sys.argv[2]
idle = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
gi.require_version("Gtk", "4.0" if kit == "4" else "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

if kit == "3":
    Gtk.init(None)
win = Gtk.Window(title=f"kg9-bars-gtk{kit}")
win.set_default_size(420, 360)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
for i in range(120):
    label = Gtk.Label(label=f"Line {i + 1} of a list longer than its window")
    label.set_xalign(0)
    box.append(label) if kit == "4" else box.pack_start(label, False, False, 0)
sw = Gtk.ScrolledWindow()
sw.set_vexpand(True)
if kit == "4":
    sw.set_child(box)
    win.set_child(sw)
    win.present()
else:
    sw.add(box)
    win.add(sw)
    win.show_all()
loop = GLib.MainLoop()


def report():
    settings = Gtk.Settings.get_default()
    vs = sw.get_vscrollbar()
    if kit == "4":
        classes, width = list(vs.get_css_classes()), vs.get_width()
        steppers = []
        child = vs.get_first_child()
        while child is not None:
            if child.get_css_name() == "stepper":
                steppers.append([child.get_width(), child.get_height()])
            child = child.get_next_sibling()
    else:
        classes, width, steppers = list(vs.get_style_context().list_classes()), vs.get_allocated_width(), None
    data = {"toolkit": kit, "gtk": "%d.%d.%d" % (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version()),
            "theme": settings.props.gtk_theme_name, "overlay_setting": settings.props.gtk_overlay_scrolling,
            "overlay_property": sw.get_overlay_scrolling(), "classes": classes, "opacity": vs.get_opacity(),
            "width": width, "mapped": vs.get_mapped(), "steppers": steppers}
    with open(out, "w") as stream:
        json.dump(data, stream)
    print(json.dumps(data), flush=True)
    return False


GLib.timeout_add(int(idle * 1000), report)
GLib.timeout_add(int(idle * 1000) + 6000, loop.quit)
loop.run()
