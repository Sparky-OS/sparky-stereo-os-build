#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""gallery_gtk3.py OUT.json: the Qt gallery's controls (rig/m9/gallery.py) in GTK 3, in one window at the screen's
top left; once drawn it writes where the File menu and the OK button are, and the theme GTK loaded, to OUT.json, so a
driver can open the menu and point at the button with real input. GTK_THEME or the session names the theme."""
import json
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402


def frame(title, child):
    f = Gtk.Frame(label=title)
    child.set_border_width(6)
    f.add(child)
    return f


def build(win):
    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    bar = Gtk.MenuBar()
    items = {}
    for title in ("File", "Edit", "View", "Special"):
        item = Gtk.MenuItem(label=title)
        menu = Gtk.Menu()
        if title == "File":
            for t in ("Open", "Close"):
                menu.append(Gtk.MenuItem(label=t))
            menu.append(Gtk.SeparatorMenuItem())
            recent = Gtk.MenuItem(label="Recent")
            sub = Gtk.Menu()
            sub.append(Gtk.MenuItem(label="One"))
            recent.set_submenu(sub)
            menu.append(recent)
        else:
            menu.append(Gtk.MenuItem(label="Item"))
        item.set_submenu(menu)
        bar.append(item)
        items[title] = item
    outer.pack_start(bar, False, False, 0)
    grid = Gtk.Grid(column_spacing=8, row_spacing=8, margin=8)
    outer.pack_start(grid, True, True, 0)

    bl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    ok = Gtk.Button(label="OK")
    ok.set_can_default(True)
    ok.set_tooltip_text("A tooltip, the help tag")
    bl.pack_start(ok, False, False, 0)
    bl.pack_start(Gtk.Button(label="Cancel"), False, False, 0)
    pressed = Gtk.Button(label="Pressed")
    pressed.set_state_flags(Gtk.StateFlags.ACTIVE, False)
    bl.pack_start(pressed, False, False, 0)
    dis = Gtk.Button(label="Disabled")
    dis.set_sensitive(False)
    bl.pack_start(dis, False, False, 0)
    tb = Gtk.Toolbar()
    tb.set_style(Gtk.ToolbarStyle.TEXT)
    for i, text in enumerate(("Bevel", "Tool", "On")):
        t = Gtk.ToggleToolButton(label=text)
        t.set_active(i == 2)
        tb.insert(t, -1)
    bl.pack_start(tb, False, False, 0)
    grid.attach(frame("Buttons", bl), 0, 0, 1, 1)

    cl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    for text, active, mixed in (("Checked", True, False), ("Unchecked", False, False), ("Mixed", False, True)):
        cb = Gtk.CheckButton(label=text)
        cb.set_active(active)
        cb.set_inconsistent(mixed)
        cl.pack_start(cb, False, False, 0)
    r1 = Gtk.RadioButton(label="Radio on")
    r2 = Gtk.RadioButton.new_with_label_from_widget(r1, "Radio off")
    r1.set_active(True)
    cl.pack_start(r1, False, False, 0)
    cl.pack_start(r2, False, False, 0)
    cd = Gtk.CheckButton(label="Disabled")
    cd.set_sensitive(False)
    cl.pack_start(cd, False, False, 0)
    grid.attach(frame("Choices", cl), 1, 0, 1, 1)

    fl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    combo = Gtk.ComboBoxText()
    for t in ("Pop-up menu", "Second"):
        combo.append_text(t)
    combo.set_active(0)
    fl.pack_start(combo, False, False, 0)
    editable = Gtk.ComboBoxText.new_with_entry()
    editable.append_text("Combo box")
    editable.set_active(0)
    fl.pack_start(editable, False, False, 0)
    entry = Gtk.Entry()
    entry.set_text("Text field")
    fl.pack_start(entry, False, False, 0)
    spin = Gtk.SpinButton.new_with_range(0, 99, 1)
    spin.set_value(9)
    fl.pack_start(spin, False, False, 0)
    grid.attach(frame("Fields", fl), 2, 0, 1, 1)

    rl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
    scale.set_draw_value(False)
    scale.set_value(40)
    rl.pack_start(scale, False, False, 0)
    p = Gtk.ProgressBar()
    p.set_fraction(0.62)
    rl.pack_start(p, False, False, 0)
    busy = Gtk.ProgressBar()
    busy.pulse()
    rl.pack_start(busy, False, False, 0)
    hs = Gtk.Scrollbar(orientation=Gtk.Orientation.HORIZONTAL, adjustment=Gtk.Adjustment(20, 0, 100, 1, 30, 30))
    rl.pack_start(hs, False, False, 0)
    grid.attach(frame("Ranges", rl), 0, 1, 1, 1)

    nb = Gtk.Notebook()
    for t in ("General", "Fonts", "Desktop"):
        lab = Gtk.Label(label=f"{t} page")
        lab.set_size_request(220, 90)
        nb.append_page(lab, Gtk.Label(label=t))
    grid.attach(nb, 1, 1, 1, 1)

    vs = Gtk.Scrollbar(orientation=Gtk.Orientation.VERTICAL, adjustment=Gtk.Adjustment(30, 0, 100, 1, 25, 25))
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
    sw.set_shadow_type(Gtk.ShadowType.IN)
    sw.set_size_request(-1, 150)
    sw.add(tree)
    grid.attach(sw, 0, 2, 2, 1)

    ls = Gtk.ListStore(str, str)
    for i in range(3):
        ls.append(["", ""])
    table = Gtk.TreeView(model=ls)
    for i, t in enumerate(("Column", "Value")):
        col = Gtk.TreeViewColumn(t, Gtk.CellRendererText(), text=i)
        col.set_clickable(True)
        table.append_column(col)
    table.get_column(0).set_sort_indicator(True)
    sw2 = Gtk.ScrolledWindow()
    sw2.set_shadow_type(Gtk.ShadowType.IN)
    sw2.add(table)
    grid.attach(sw2, 2, 2, 1, 1)
    win.add(outer)
    win.kg9_bars = {"h": hs, "v": vs}
    return items, ok


def report(win, items, ok, out):
    def centre(w):
        a = w.get_allocation()
        x, y = w.translate_coordinates(win, 0, 0)
        return [x + a.width // 2, y + a.height // 2]
    def rect(w):
        a = w.get_allocation()
        x, y = w.translate_coordinates(win, 0, 0)
        return [x, y, a.width, a.height]
    settings = Gtk.Settings.get_default()
    data = {"file": centre(items["File"]), "ok": centre(ok), "bars": {k: rect(v) for k, v in win.kg9_bars.items()}, "theme": settings.props.gtk_theme_name,
            "overlay": settings.props.gtk_overlay_scrolling, "gtk": "%d.%d.%d" % (Gtk.get_major_version(),
            Gtk.get_minor_version(), Gtk.get_micro_version()), "size": [win.get_allocated_width(), win.get_allocated_height()]}
    with open(out, "w") as f:
        json.dump(data, f)
    print(json.dumps(data), flush=True)
    return False


def main():
    out = sys.argv[1]
    win = Gtk.Window(title="Kubabbar Glass 9 gallery, GTK 3")
    win.set_default_size(860, 600)
    items, ok = build(win)
    win.move(0, 0)
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    ok.grab_default()
    GLib.timeout_add(800, report, win, items, ok, out)
    Gtk.main()


if __name__ == "__main__":
    main()
