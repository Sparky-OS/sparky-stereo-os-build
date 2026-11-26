#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""gallery_gtk4.py OUT.json: the Qt gallery's controls (rig/m9/gallery.py) in GTK 4, in one window; once drawn it
writes where the File menu and the OK button are, and the theme GTK loaded, to OUT.json (see gallery_gtk3.py)."""
import json
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402


def frame(title, child):
    f = Gtk.Frame(label=title)
    child.set_margin_start(6)
    child.set_margin_end(6)
    child.set_margin_top(6)
    child.set_margin_bottom(6)
    f.set_child(child)
    return f


def vbox(spacing=4):
    return Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing)


def build(app, win):
    outer = vbox(6)
    model = Gio.Menu()
    for title in ("File", "Edit", "View", "Special"):
        sub = Gio.Menu()
        if title == "File":
            sub.append("Open", "app.none")
            sub.append("Close", "app.none")
            section = Gio.Menu()
            recent = Gio.Menu()
            recent.append("One", "app.none")
            section.append_submenu("Recent", recent)
            sub.append_section(None, section)
        else:
            sub.append("Item", "app.none")
        model.append_submenu(title, sub)
    bar = Gtk.PopoverMenuBar.new_from_model(model)
    outer.append(bar)
    grid = Gtk.Grid(column_spacing=8, row_spacing=8)
    grid.set_margin_start(8)
    grid.set_margin_end(8)
    outer.append(grid)

    bl = vbox()
    ok = Gtk.Button(label="OK")
    ok.set_tooltip_text("A tooltip, the help tag")
    bl.append(ok)
    bl.append(Gtk.Button(label="Cancel"))
    pressed = Gtk.Button(label="Pressed")
    pressed.set_state_flags(Gtk.StateFlags.ACTIVE, False)
    bl.append(pressed)
    dis = Gtk.Button(label="Disabled")
    dis.set_sensitive(False)
    bl.append(dis)
    tb = Gtk.Box(spacing=2)
    tb.add_css_class("toolbar")
    for i, text in enumerate(("Bevel", "Tool", "On")):
        t = Gtk.ToggleButton(label=text)
        t.add_css_class("flat")
        t.set_active(i == 2)
        tb.append(t)
    bl.append(tb)
    grid.attach(frame("Buttons", bl), 0, 0, 1, 1)

    cl = vbox(2)
    for text, active, mixed in (("Checked", True, False), ("Unchecked", False, False), ("Mixed", False, True)):
        cb = Gtk.CheckButton(label=text)
        cb.set_active(active)
        cb.set_inconsistent(mixed)
        cl.append(cb)
    r1 = Gtk.CheckButton(label="Radio on")
    r2 = Gtk.CheckButton(label="Radio off")
    r2.set_group(r1)
    r1.set_active(True)
    cl.append(r1)
    cl.append(r2)
    cd = Gtk.CheckButton(label="Disabled")
    cd.set_sensitive(False)
    cl.append(cd)
    grid.attach(frame("Choices", cl), 1, 0, 1, 1)

    fl = vbox()
    dd = Gtk.DropDown.new_from_strings(["Pop-up menu", "Second"])
    fl.append(dd)
    editable = Gtk.ComboBoxText.new_with_entry()
    editable.append_text("Combo box")
    editable.set_active(0)
    fl.append(editable)
    entry = Gtk.Entry()
    entry.set_text("Text field")
    fl.append(entry)
    spin = Gtk.SpinButton.new_with_range(0, 99, 1)
    spin.set_value(9)
    fl.append(spin)
    grid.attach(frame("Fields", fl), 2, 0, 1, 1)

    rl = vbox(6)
    scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
    scale.set_value(40)
    rl.append(scale)
    p = Gtk.ProgressBar()
    p.set_fraction(0.62)
    rl.append(p)
    busy = Gtk.ProgressBar()
    busy.pulse()
    rl.append(busy)
    hs = Gtk.Scrollbar(orientation=Gtk.Orientation.HORIZONTAL,
                       adjustment=Gtk.Adjustment(value=20, lower=0, upper=100, step_increment=1, page_increment=30,
                                                 page_size=30))
    rl.append(hs)
    grid.attach(frame("Ranges", rl), 0, 1, 1, 1)

    nb = Gtk.Notebook()
    for t in ("General", "Fonts", "Desktop"):
        lab = Gtk.Label(label=f"{t} page")
        lab.set_size_request(220, 90)
        nb.append_page(lab, Gtk.Label(label=t))
    grid.attach(nb, 1, 1, 1, 1)

    vs = Gtk.Scrollbar(orientation=Gtk.Orientation.VERTICAL,
                       adjustment=Gtk.Adjustment(value=30, lower=0, upper=100, step_increment=1, page_increment=25,
                                                 page_size=25))
    vs.set_size_request(-1, 150)
    vs.set_halign(Gtk.Align.START)
    grid.attach(vs, 2, 1, 1, 1)

    store = Gtk.TreeStore(str, str, str)
    for folder in ("System Folder", "Documents"):
        it = store.append(None, [folder, "--", "folder"])
        for child in ("Item one", "Item two"):
            store.append(it, [child, "12 KB", "document"])
    tree = Gtk.TreeView(model=store)
    for i, t in enumerate(("Name", "Size", "Kind")):
        col = Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i)
        col.set_clickable(True)
        tree.append_column(col)
    tree.expand_row(Gtk.TreePath.new_first(), False)
    tree.get_selection().select_path(Gtk.TreePath.new_from_string("0:0"))
    sw = Gtk.ScrolledWindow()
    sw.set_has_frame(True)
    sw.set_size_request(-1, 150)
    sw.set_child(tree)
    grid.attach(sw, 0, 2, 2, 1)

    strings = Gtk.StringList.new(["", "", ""])
    cv = Gtk.ColumnView(model=Gtk.SingleSelection(model=strings))
    for t in ("Column", "Value"):
        f = Gtk.SignalListItemFactory()
        f.connect("setup", lambda _f, li: li.set_child(Gtk.Label()))
        cv.append_column(Gtk.ColumnViewColumn(title=t, factory=f))
    sw2 = Gtk.ScrolledWindow()
    sw2.set_has_frame(True)
    sw2.set_child(cv)
    grid.attach(sw2, 2, 2, 1, 1)
    win.set_child(outer)
    win.set_default_widget(ok)
    win.kg9_bars = {"h": hs, "v": vs}
    return bar, ok


def report(win, bar, ok, out):
    def centre(w):
        ok_, b = w.compute_bounds(win)
        return [round(b.get_x() + b.get_width() / 2), round(b.get_y() + b.get_height() / 2)]
    # the menu bar's first item: its first child widget
    first = bar.get_first_child()
    while first is not None and first.get_first_child() is not None and first.get_css_name() != "item":
        first = first.get_first_child()
    def rect(w):
        ok_, b = w.compute_bounds(win)
        return [round(b.get_x()), round(b.get_y()), round(b.get_width()), round(b.get_height())]
    settings = Gtk.Settings.get_default()
    data = {"file": centre(first if first is not None else bar), "ok": centre(ok), "bars": {k: rect(v) for k, v in win.kg9_bars.items()}, "theme": settings.props.gtk_theme_name,
            "overlay": settings.props.gtk_overlay_scrolling,
            "gtk": "%d.%d.%d" % (Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version()),
            "size": [win.get_width(), win.get_height()]}
    with open(out, "w") as f:
        json.dump(data, f)
    print(json.dumps(data), flush=True)
    return False


def main():
    out = sys.argv[1]
    app = Gtk.Application(application_id="org.sparkystereo.Gallery4", flags=Gio.ApplicationFlags.NON_UNIQUE)

    def activate(app):
        app.add_action(Gio.SimpleAction.new("none", None))
        win = Gtk.ApplicationWindow(application=app, title="Kubabbar Glass 9 gallery, GTK 4")
        win.set_default_size(860, 600)
        win.set_decorated(False)
        bar, ok = build(app, win)
        win.present()
        GLib.timeout_add(1200, report, win, bar, ok, out)
    app.connect("activate", activate)
    app.run([])


if __name__ == "__main__":
    main()
