#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""GTK 4's scroll arrows (the edition's gtk4 +stereo3d4, row 147 milestone 3), from the installed library, in a real
window under an X server: the stepper nodes and their order; no room taken under a theme without stepper rules; the
two of each placement shown when a theme sizes them; their sensitivity at both ends and in right-to-left text; and
real pointer input through xdotool: a click moves one step, a held button keeps scrolling, the secondary button moves
a page, the middle one jumps to the end. Prints one JSON line per row and exits 1 when a row fails.
Usage (DISPLAY set, xdotool installed): gtk4-steppers.py OUT.json"""
import json
import subprocess
import sys
import time

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Graphene", "1.0")
from gi.repository import GLib, Graphene, Gtk  # noqa: E402

out = sys.argv[1]
rows = []


def row(name, ok, **facts):
    rows.append(dict(row=name, passed=bool(ok), **facts))
    print(json.dumps(rows[-1]), flush=True)


def spin(seconds):
    end = time.monotonic() + seconds
    ctx = GLib.MainContext.default()
    while time.monotonic() < end:
        while ctx.pending():
            ctx.iteration(False)
        time.sleep(0.01)


TOGETHER = "scrollbar > range ~ stepper { min-width: 16px; min-height: 16px; }"
APART = ("scrollbar > stepper.up:first-child, scrollbar > stepper.down:last-child "
         "{ min-width: 16px; min-height: 16px; }")
provider = Gtk.CssProvider()

win = Gtk.Window(title="steppers")
win.set_decorated(False)
win.set_default_size(300, 300)
box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
win.set_child(box)
adj = Gtk.Adjustment(value=0, lower=0, upper=100, step_increment=1, page_increment=10, page_size=10)
vbar = Gtk.Scrollbar(orientation=Gtk.Orientation.VERTICAL, adjustment=adj)
vbar.set_vexpand(True)
box.append(Gtk.Label(label="steppers", hexpand=True))
box.append(vbar)
hadj = Gtk.Adjustment(value=0, lower=0, upper=100, step_increment=1, page_increment=10, page_size=10)
hbar = Gtk.Scrollbar(orientation=Gtk.Orientation.HORIZONTAL, adjustment=hadj)
win.present()
spin(1.0)


def children(bar):
    out = []
    child = bar.get_first_child()
    while child is not None:
        out.append(child)
        child = child.get_next_sibling()
    return out


def steppers(bar):
    return [c for c in children(bar) if c.get_css_name() == "stepper"]


def lengths(bar):
    vertical = bar.get_orientation() == Gtk.Orientation.VERTICAL
    return [(c.get_css_name(), "up" if c.has_css_class("up") else "down" if c.has_css_class("down") else "",
             c.get_height() if vertical else c.get_width()) for c in children(bar)]


nodes = [(c.get_css_name(), "up" if c.has_css_class("up") else "down" if c.has_css_class("down") else "")
         for c in children(vbar)]
row("nodes", nodes == [("stepper", "up"), ("stepper", "down"), ("range", ""), ("stepper", "up"), ("stepper", "down")],
    nodes=nodes)
if len(steppers(vbar)) != 4:
    with open(out, "w") as stream:
        json.dump(rows, stream, indent=1)
    print("1 row, 1 failed ['nodes']: this GTK 4 has no stepper nodes", flush=True)
    sys.exit(1)

# GTK's own theme has no stepper rules: every stepper takes no room, the range takes the whole bar
total = vbar.get_height()
ls = lengths(vbar)
row("default-no-room", len(steppers(vbar)) == 4 and all(n == 0 for name, _, n in ls if name == "stepper")
    and [n for name, _, n in ls if name == "range"] == [total], lengths=ls, bar=total)


def with_css(css):
    provider.load_from_string(css)
    Gtk.StyleContext.add_provider_for_display(win.get_display(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    spin(0.5)


def placement(name, css, shown):
    with_css(css)
    ls = lengths(vbar)
    sizes = [n for nm, _, n in ls if nm == "stepper"]
    rng = [n for nm, _, n in ls if nm == "range"][0]
    expected = [16 if i in shown else 0 for i in range(4)]
    row(name, sizes == expected and rng == vbar.get_height() - 32, sizes=sizes, range=rng, bar=vbar.get_height())


placement("together-sizes", TOGETHER, (2, 3))
placement("apart-sizes", APART, (0, 3))


def sens(bar):
    return [s.get_sensitive() for s in steppers(bar)]


adj.set_value(0)
spin(0.3)
row("sensitive-at-start", sens(vbar) == [False, True, False, True], sensitive=sens(vbar))
adj.set_value(90)
spin(0.3)
row("sensitive-at-end", sens(vbar) == [True, False, True, False], sensitive=sens(vbar))
adj.set_value(50)
spin(0.3)
row("sensitive-in-middle", sens(vbar) == [True, True, True, True], sensitive=sens(vbar))

# right-to-left: a horizontal range is flipped, so the left steppers move the value forward
box.append(hbar)
hbar.set_direction(Gtk.TextDirection.RTL)
hadj.set_value(0)
spin(0.5)
row("rtl-at-start", sens(hbar) == [True, False, True, False], sensitive=sens(hbar))
box.remove(hbar)


def centre(widget):
    ok, p = widget.compute_point(win, Graphene.Point().init(widget.get_width() / 2, widget.get_height() / 2))
    return int(p.x), int(p.y)


def window_origin():
    wid = subprocess.run(["xdotool", "search", "--name", "^steppers$"], capture_output=True, text=True).stdout.split()
    geo = subprocess.run(["xdotool", "getwindowgeometry", "--shell", wid[0]], capture_output=True, text=True).stdout
    vals = dict(line.split("=") for line in geo.split())
    return int(vals["X"]), int(vals["Y"])


def press(widget, button, hold):
    ox, oy = window_origin()
    x, y = centre(widget)
    subprocess.run(["xdotool", "mousemove", str(ox + x), str(oy + y)], check=True)
    spin(0.2)
    subprocess.run(["xdotool", "mousedown", str(button)], check=True)
    spin(hold)
    subprocess.run(["xdotool", "mouseup", str(button)], check=True)
    spin(0.6)


with_css(TOGETHER)
down = steppers(vbar)[3]
up = steppers(vbar)[2]
adj.set_value(50)
spin(0.5)
press(down, 1, 0.1)
row("click-steps-forward", abs(adj.get_value() - 51) < 1e-6, value=adj.get_value())
press(up, 1, 0.1)
row("click-steps-back", abs(adj.get_value() - 50) < 1e-6, value=adj.get_value())
press(down, 1, 1.5)
row("hold-keeps-scrolling", adj.get_value() > 52, value=adj.get_value())
adj.set_value(50)
spin(0.5)
press(down, 3, 0.1)
row("secondary-moves-a-page", abs(adj.get_value() - 60) < 1e-6, value=adj.get_value())
press(down, 2, 0.1)
row("middle-jumps-to-end", abs(adj.get_value() - 90) < 1e-6 and not down.get_sensitive(), value=adj.get_value(),
    forward_sensitive=down.get_sensitive())
press(up, 2, 0.1)
row("middle-jumps-to-start", abs(adj.get_value()) < 1e-6 and not up.get_sensitive(), value=adj.get_value())

win.destroy()
spin(0.2)
with open(out, "w") as stream:
    json.dump(rows, stream, indent=1)
failed = [r["row"] for r in rows if not r["passed"]]
print(f"{len(rows)} rows, {len(failed)} failed {failed}", flush=True)
sys.exit(1 if failed else 0)
