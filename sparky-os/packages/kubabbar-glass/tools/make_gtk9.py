#!/usr/bin/env python3
"""Kubabbar Glass 9's GTK 2, GTK 3 and GTK 4 themes: the classic controls of its Kvantum themes, drawn from the same
pixels (make_kvantum9.elements), one theme per accent variation, each with an "Apart" theme for the scroll arrows at
both ends.

- The pictures: every control and state of the Kvantum theme, put back together from Kvantum's nine parts into one PNG
  (assets/), shared by the three toolkits of a theme.
- GTK 2: a theme of its own on GTK 2's pixmap engine (gtk2-engines-pixbuf), the pictures cut at Kvantum's frame widths.
- GTK 3 and GTK 4: the Breeze GTK shapes in the accent's KDE colour scheme (tools/kde2gtk_colors.py, as the family's GTK
  themes), then the classic controls drawn over them with border-image and -gtk-icon-source. Breeze's own rules are
  specific (button:hover:not(:checked):not(:active)); every classic rule carries PAD, five :not() of classes no widget
  has, so it outranks them without listing each of Breeze's cases.
- Scroll arrows: GTK 2 and GTK 3 have the four steppers of GtkRange (backward, forward and their secondary twins at the
  other end); together is the secondary backward stepper beside the forward one, apart the two plain ones. GTK 4 has
  no scroll arrows (its library has no stepper at all), so both of its themes draw the bar the same, scroll box and track.
GPL-3.0-only."""
import configparser
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import make_kvantum9 as kv  # noqa: E402
from platinum9 import ACCENTS, DEFAULT_ACCENT, OUTLINE, TOOLTIP, scheme_id  # noqa: E402

ROOT = HERE.parent
THEMES = ROOT / "share/themes"
PAD = "".join(f":not(.kg9-{c})" for c in "abcde")
STATE_GTK3 = {"normal": "", "focused": ":hover", "pressed": ":active", "toggled": ":checked", "disabled": ":disabled"}


def gtk_name(accent, together=True):
    base = "Kubabbar-Glass-9" + ("" if accent == DEFAULT_ACCENT else "-" + accent.capitalize())
    return base if together else base + "-Apart"


# ---------------------------------------------------------------- the pictures
def assemble(out, prefix):
    """The control's whole picture from Kvantum's nine parts, and its frame widths (top, bottom, left, right)."""
    tl, br = out[prefix + "-topleft"], out[prefix + "-bottomright"]
    part = dict((p, out[prefix + p]) for p in ("-topleft", "-top", "-topright", "-left", "", "-right", "-bottomleft",
                                                 "-bottom", "-bottomright"))
    # an interior Kvantum must find empty (the default ring's) is a 1x1 transparent part there: an empty one of its size
    h, w = part["-left"].shape[0], part["-top"].shape[1]
    if part[""].shape[:2] != (h, w):
        part[""] = np.zeros((h, w, 4))
    rows = []
    for parts in (("-topleft", "-top", "-topright"), ("-left", "", "-right"), ("-bottomleft", "-bottom", "-bottomright")):
        rows.append(np.concatenate([part[p] for p in parts], axis=1))
    return np.concatenate(rows, axis=0), (tl.shape[0], br.shape[0], tl.shape[1], br.shape[1])


def over(top, bottom):
    """Straight-alpha composite of top over bottom."""
    ta, ba = top[..., 3:4], bottom[..., 3:4]
    a = ta + ba * (1 - ta)
    rgb = np.where(a > 0, (top[..., :3] * ta + bottom[..., :3] * ba * (1 - ta)) / np.maximum(a, 1e-9), 0)
    return np.concatenate([rgb, a], axis=2)


def png(arr, path):
    rgba = np.concatenate([np.clip(np.round(arr[..., :3]), 0, 255), np.clip(np.round(arr[..., 3:4] * 255), 0, 255)], axis=2)
    Image.fromarray(rgba.astype(np.uint8), "RGBA").save(path, optimize=True)


def transpose(arr):
    return np.transpose(arr, (1, 0, 2))


def pictures(accent):
    """name -> (array, (top, bottom, left, right) or None)"""
    e = kv.elements(accent)
    pics = {}
    framed = ["button", "tbutton", "combo", "spin", "lineedit", "common", "group", "tab", "tabframe", "header", "toolbar",
              "slider", "progress", "sgroove", "scrollbarslider", "menu", "menubar", "tooltip"]
    for name in framed:
        for state in kv.STATES:
            if f"{name}-{state}-topleft" in e:
                pics[f"{name}-{state}"] = assemble(e, f"{name}-{state}")
    ring, _ = assemble(e, "button-default")
    for state in kv.STATES:
        arr, f = pics[f"button-{state}"]
        pics[f"button-default-{state}"] = (over(ring, arr), f)
    focus, f = assemble(e, "focus")
    pics["focus"] = (focus, f)
    for state in kv.STATES:
        if f"sgroove-{state}" in pics:
            arr, (t, b, l, r) = pics[f"sgroove-{state}"]
            pics[f"sgroove-h-{state}"] = (transpose(arr), (l, r, t, b))
    single = [k for k in e if k.startswith(("checkbox-", "radio-", "slidercursor-", "progress-pattern-", "grip-", "arrow-",
                                            "sarrowbox-", "popuparrow-", "disclosure-", "menuitem-right-", "menuitem-left-"))
              and not k.endswith(("-top", "-bottom", "-left", "-right", "-topleft", "-topright", "-bottomleft",
                                  "-bottomright"))]
    for k in single:
        pics[k] = (e[k], None)
    for state in kv.STATES:
        if f"grip-{state}" in e:
            pics[f"grip-h-{state}"] = (transpose(e[f"grip-{state}"]), None)
        pics[f"sarrowbox-left-{state}"] = (transpose(e[f"sarrowbox-up-{state}"]), None)
        pics[f"sarrowbox-right-{state}"] = (transpose(e[f"sarrowbox-down-{state}"]), None)
    pics["menuitem-separator"] = (e["menuitem-separator"], None)
    pics["toolbar-separator"] = (e["toolbar-separator"], None)
    pics["toolbar-handle"] = (e["toolbar-handle"], None)
    return pics


# ---------------------------------------------------------------- GTK 3 and GTK 4
def img(name):
    return f'url("../assets/{name}.png")'


def centre(pics, name):
    """The colour of a picture's interior, or None when the interior is empty (frames around other content)."""
    arr, (t, b, l, r) = pics[name]
    mid = arr[t:arr.shape[0] - b, l:arr.shape[1] - r]
    if mid.size == 0 or mid[..., 3].max() == 0:
        return None
    colours = {tuple(px[:3]) for px in mid.reshape(-1, 4) if px[3] > 0}
    if len(colours) != 1 or mid[..., 3].min() < 1:
        raise SystemExit(f"{name}: its interior is not one opaque colour, so it cannot be the box's background")
    return css_rgb(tuple(int(v) for v in colours.pop()))


def bimg(pics, name, fill=True):
    """The picture as the box's border, at its own frame widths (the edges stretched along their length, as Kvantum
    stretches its nine parts), and its interior as the box's background inside that border. GTK 3 ignores
    border-image's fill keyword, so the interior is never left to it; the border widths are real, so the background
    starts where the picture's interior starts."""
    t, b, l, r = pics[name][1]
    face = centre(pics, name) if fill else None
    return (f"border-image: {img(name)} {t} {r} {b} {l} stretch; border-style: solid; border-color: transparent; "
            f"border-width: {t}px {r}px {b}px {l}px; border-radius: 0; box-shadow: none; background-image: none; "
            f"background-clip: padding-box; background-color: {face or 'transparent'}; outline-color: transparent;")


def states(selector, pics, base, extra="", fill=True, toggled=True, sel_suffix=""):
    """One rule per Kvantum state; toggled (checked) is drawn as pressed when the theme has no toggled picture."""
    rules = []
    for state, pseudo in STATE_GTK3.items():
        if state == "toggled" and not toggled:
            continue
        name = f"{base}-{state}"
        if name not in pics:
            name = f"{base}-pressed" if state == "toggled" and f"{base}-pressed" in pics else f"{base}-normal"
        sel = ", ".join(f"{s}{PAD}{pseudo}{sel_suffix}" for s in selector.split(", "))
        if state == "focused":
            sel = ", ".join(f"{s}{PAD}:hover:not(:active):not(:checked){sel_suffix}" for s in selector.split(", "))
        rules.append(f"{sel} {{ {bimg(pics, name, fill)} {extra}}}")
    return rules


def icon_states(selector, pics, base, checked=None, mixed=None, size=13, gtk=3):
    """Check boxes and radio buttons: the picture as the indicator's icon, per state and mark."""
    marks = [("", base), (":checked", checked), (":indeterminate", mixed)]
    rules = [f"{selector}{PAD} {{ min-width: {size}px; min-height: {size}px; margin: 0 4px 0 0; padding: 0; "
             "border: none; border-radius: 0; box-shadow: none; background: none; outline-color: transparent; "
             "-gtk-icon-shadow: none; }"]
    for mark, picture in marks:
        if not picture:
            continue
        for state, pseudo in (("normal", ""), ("focused", ":hover"), ("pressed", ":active"), ("disabled", ":disabled")):
            name = f"{picture}-{state}"
            rules.append(f"{selector}{PAD}{mark}{pseudo} {{ -gtk-icon-source: {img(name)}; background-image: none; }}")
    return rules


def classic_css(pics, together, gtk):
    """The classic controls over Breeze, for GTK 3 or GTK 4 (gtk = 3 or 4)."""
    face, view = "@theme_bg_color_breeze", "@theme_base_color_breeze"
    css = ["/* Kubabbar Glass 9: the classic controls, the pictures of its Kvantum theme (tools/make_gtk9.py). */",
           f"*{PAD}:disabled, *{PAD}:disabled > label {{ color: {INACTIVE_CUR[0]}; }}"]
    # push buttons, the default one ringed, and their pressed text in white as Kvantum draws it
    css += states("button", pics, "button", "padding: 1px 6px; min-height: 16px; min-width: 16px; ")
    css += [f"button{PAD}:active, button{PAD}:checked, button{PAD}:active > label, button{PAD}:checked > label "
            "{ color: #ffffff; }"]
    default = "button.default" if gtk == 3 else "button.default, window.dialog button.default"
    css += states(default, pics, "button-default")
    # bevel (tool) buttons: flat buttons and tool bar buttons draw the bevel when pointed at, pressed or on
    flat = "button.flat, toolbar button, headerbar button, .toolbar button"
    css += states(flat, pics, "tbutton", "padding: 1px 3px; ")
    css += [f"{s}{PAD}:not(:hover):not(:active):not(:checked) {{ border-image: none; background: none; }}"
            for s in ("button.flat",)]
    css += [f"{s}{PAD}:active, {s}{PAD}:checked, {s}{PAD}:active > label, {s}{PAD}:checked > label {{ color: @theme_fg_color_breeze; }}"
            for s in flat.split(", ")]
    # pop-up menus (combo boxes and GTK 4's drop-downs): a rounded bevel with the down arrow
    combo = "combobox button.combo, combobox > box > button.combo" if gtk == 3 else "dropdown > button, combobox button.combo"
    css += states(combo, pics, "combo", "padding: 1px 4px; ")
    css += [f"{s}{PAD}:active, {s}{PAD}:checked, {s}{PAD}:active > label {{ color: @theme_fg_color_breeze; }}"
            for s in combo.split(", ")]
    arrow = "combobox arrow" if gtk == 3 else "dropdown arrow, combobox arrow"
    for state, pseudo in (("normal", ""), ("disabled", ":disabled")):
        css.append(f"{', '.join(s + PAD + pseudo for s in arrow.split(', '))} {{ -gtk-icon-source: {img('popuparrow-' + state)}; "
                   "min-width: 10px; min-height: 10px; -gtk-icon-transform: none; }")
    # text fields: the sunken edge, the focus ring in the accent
    entry = "entry" if gtk == 3 else "entry, spinbutton, text.entry"
    css += [f"{', '.join(s + PAD for s in entry.split(', '))} {{ {bimg(pics, 'lineedit-normal')} padding: 1px 3px; "
            f"min-height: 16px; background-color: transparent; color: @theme_text_color_breeze; }}",
            f"{', '.join(s + PAD + ':focus-within' if gtk == 4 else s + PAD + ':focus' for s in entry.split(', '))} "
            f"{{ {bimg(pics, 'lineedit-focused')} }}",
            f"{', '.join(s + PAD + ':disabled' for s in entry.split(', '))} {{ {bimg(pics, 'lineedit-disabled')} }}"]
    # spin buttons: the little bevelled arrow boxes
    spin = "spinbutton button" if gtk == 3 else "spinbutton > button"
    css += states(spin, pics, "spin", "padding: 0 1px; min-width: 12px; color: @theme_fg_color_breeze; ", toggled=False)
    # the spin button's signs are icons GTK names in its code (list-add, list-remove), so the theme hides them (a symbolic
    # icon takes the text colour) and draws the classic arrow under them
    for d, cls in (("up", "up"), ("down", "down")):
        for state, pseudo in (("normal", ""), ("focused", ":hover"), ("pressed", ":active"), ("disabled", ":disabled")):
            css.append(f"spinbutton{PAD} button.{cls}{PAD}{pseudo} {{ color: transparent; -gtk-icon-shadow: none; "
                       f"background-image: {img('arrow-' + d + '-' + ('disabled' if state == 'disabled' else 'normal'))}; "
                       "background-repeat: no-repeat; background-position: center; }")
    if gtk == 4:
        # GTK 4's spin buttons are buttons with an image child: the image is hidden, the arrow drawn under it
        css.append(f"spinbutton{PAD} > button{PAD} > image {{ opacity: 0; }}")
    # check boxes and radio buttons
    check = "check" if gtk == 3 else "checkbutton check, check"
    for sel in check.split(", "):
        css += icon_states(sel, pics, "checkbox", "checkbox-checked", "checkbox-tristate", gtk=gtk)
    radio = "radio" if gtk == 3 else "checkbutton radio, radio"
    for sel in radio.split(", "):
        css += icon_states(sel, pics, "radio", "radio-checked", None, gtk=gtk)
    # tabs: rounded top corners; the current one open into its page
    css += states("notebook > header > tabs > tab", pics, "tab", "padding: 1px 6px 1px 6px; margin: 0 -1px 0 0; ",
                  toggled=False)
    css += [f"notebook > header > tabs > tab{PAD}:checked {{ {bimg(pics, 'tab-toggled')} }}",
            f"notebook > header{PAD} {{ background: none; border: none; box-shadow: none; padding: 0 4px; }}",
            f"notebook{PAD} > stack:not(:only-child) {{ {bimg(pics, 'tabframe-normal')} background-color: {face}; }}",
            f"notebook{PAD} {{ border: none; background: none; box-shadow: none; }}"]
    # list and table headers
    header = "treeview.view header button, columnview > header > button" if gtk == 4 else "treeview.view header button"
    css += states(header, pics, "header", "padding: 1px 5px; color: @theme_fg_color_breeze; ")
    # sliders: the sunken channel and the bevelled handle with its accent centre
    scale = "scale"
    css += [f"{scale}{PAD} trough {{ {bimg(pics, 'slider-normal')} min-height: 2px; min-width: 2px; }}",
            f"{scale}{PAD}:disabled trough {{ {bimg(pics, 'slider-disabled')} }}",
            f"{scale}{PAD} highlight {{ background: none; border: none; box-shadow: none; }}",
            f"{scale}{PAD} slider {{ min-width: 16px; min-height: 16px; margin: -6px; border: none; border-radius: 0; "
            f"box-shadow: none; outline-color: transparent; background: {img('slidercursor-normal')} no-repeat center; }}"]
    for state, pseudo in (("focused", ":hover"), ("pressed", ":active"), ("disabled", ":disabled")):
        css.append(f"{scale}{PAD} slider{pseudo} {{ background: {img('slidercursor-' + state)} no-repeat center; }}")
    # progress bars: the sunken track and the accent bar with its lighter upper band
    css += [f"progressbar{PAD} trough {{ {bimg(pics, 'progress-normal')} min-height: 8px; min-width: 8px; padding: 0; }}",
            f"progressbar{PAD} progress {{ border: none; border-radius: 0; box-shadow: none; margin: 0; "
            f"background: {img('progress-pattern-normal')} repeat-x; background-size: 2px 100%; min-height: 8px; }}",
            f"progressbar{PAD}:disabled progress {{ background-image: {img('progress-pattern-disabled')}; }}"]
    # scroll bars: the track, the scroll box in the accent with its grip, the arrow boxes
    sb = "scrollbar"
    css += [f"{sb}{PAD} {{ background: none; border: none; box-shadow: none; padding: 0; margin: 0; }}",
            f"{sb}{PAD}.vertical trough, {sb}{PAD}.vertical range > trough {{ {bimg(pics, 'sgroove-normal')} min-width: 14px; padding: 0; }}",
            f"{sb}{PAD}.horizontal trough, {sb}{PAD}.horizontal range > trough {{ {bimg(pics, 'sgroove-h-normal')} min-height: 14px; padding: 0; }}",
            f"{sb}{PAD}:disabled trough {{ {bimg(pics, 'sgroove-disabled')} }}",
            f"{sb}{PAD} slider {{ {bimg(pics, 'scrollbarslider-normal')} margin: -1px; min-width: 12px; min-height: 24px; "
            f"background-image: {img('grip-normal')}; background-repeat: no-repeat; background-position: center; }}",
            f"{sb}{PAD}.horizontal slider {{ min-width: 24px; min-height: 12px; background-image: {img('grip-h-normal')}; }}",
            f"{sb}{PAD} slider:hover {{ {bimg(pics, 'scrollbarslider-focused')} background-image: {img('grip-focused')}; "
            "background-repeat: no-repeat; background-position: center; }",
            f"{sb}{PAD} slider:active, {sb}{PAD}.dragging slider {{ {bimg(pics, 'scrollbarslider-pressed')} "
            f"background-image: {img('grip-pressed')}; background-repeat: no-repeat; background-position: center; }}",
            f"{sb}{PAD}.horizontal slider:hover {{ background-image: {img('grip-h-focused')}; }}",
            f"{sb}{PAD}.horizontal slider:active, {sb}{PAD}.horizontal.dragging slider {{ background-image: {img('grip-h-pressed')}; }}",
            f"{sb}{PAD}.overlay-indicator:not(.dragging):not(.hovering) slider {{ min-width: 12px; min-height: 24px; margin: -1px; }}"]
    if gtk == 3:
        css.append(f"{sb}{PAD} {{ -GtkScrollbar-has-backward-stepper: {'false' if together else 'true'}; "
                   "-GtkScrollbar-has-forward-stepper: true; "
                   f"-GtkScrollbar-has-secondary-backward-stepper: {'true' if together else 'false'}; "
                   "-GtkScrollbar-has-secondary-forward-stepper: false; }")
        # GTK 3 names a stepper by the end it points to, up and down, in both orientations
        for orient, d, cls in (("vertical", "up", "up"), ("vertical", "down", "down"), ("horizontal", "left", "up"),
                               ("horizontal", "right", "down")):
            for state, pseudo in STATE_GTK3.items():
                if state == "toggled":
                    continue
                css.append(f"{sb}{PAD}.{orient} button.{cls}{pseudo} {{ min-width: 16px; min-height: 16px; padding: 0; margin: 0; "
                           f"border: none; border-radius: 0; box-shadow: none; -gtk-icon-source: none; color: transparent; "
                           f"background: {img('sarrowbox-' + d + '-' + state)} no-repeat center; }}")
    # menus, the menu bar and their items; tool tips
    if gtk == 3:
        css += [f"menu{PAD}, .menu{PAD}, .context-menu{PAD} {{ {bimg(pics, 'menu-normal')} padding: 2px 0; "
                f"background-color: {face}; }}",
                f"menu{PAD} menuitem, .menu{PAD} menuitem {{ padding: 2px 14px; min-height: 16px; color: @theme_fg_color_breeze; "
                "background: none; border: none; box-shadow: none; }",
                f"menu{PAD} menuitem:hover, .menu{PAD} menuitem:hover {{ background-color: {css_rgb(ACCENTS_CUR['accent'])}; "
                "color: #ffffff; }",
                f"menu{PAD} > menuitem:hover > label, menu{PAD} > menuitem:hover > box > label, menu{PAD} > menuitem:hover accelerator {{ color: #ffffff; }}",
                f"menu{PAD} menuitem arrow {{ -gtk-icon-source: {img('menuitem-right-normal')}; min-width: 10px; min-height: 10px; }}",
                f"menu{PAD} menuitem:hover arrow {{ -gtk-icon-source: {img('menuitem-right-focused')}; }}",
                f"menu{PAD} separator {{ min-height: 10px; background: {img('menuitem-separator')} repeat-x center; "
                "margin: 0; }",
                f"menubar{PAD}, .menubar{PAD} {{ {bimg(pics, 'menubar-normal')} padding: 0; background-color: {face}; }}",
                f"menubar{PAD} > menuitem {{ padding: 3px 8px; min-height: 16px; color: @theme_fg_color_breeze; "
                "background: none; border: none; box-shadow: none; }",
                f"menubar{PAD} > menuitem:hover {{ background-color: {css_rgb(ACCENTS_CUR['accent'])}; color: #ffffff; }}",
                f"menubar{PAD} > menuitem:hover > label {{ color: #ffffff; }}"]
    else:
        css += [f"popover.menu{PAD} > contents, popover{PAD} > contents {{ {bimg(pics, 'menu-normal')} padding: 2px 0; "
                f"background-color: {face}; }}",
                f"popover{PAD} > arrow {{ background: none; border: none; }}",
                f"popover.menu{PAD} modelbutton {{ padding: 2px 14px; min-height: 16px; border-radius: 0; color: @theme_fg_color_breeze; }}",
                f"popover.menu{PAD} modelbutton:hover, popover.menu{PAD} modelbutton:selected {{ background-color: "
                f"{css_rgb(ACCENTS_CUR['accent'])}; color: #ffffff; }}",
                f"popover.menu{PAD} modelbutton:hover > label, popover.menu{PAD} modelbutton:hover > accelerator {{ color: #ffffff; }}",
                f"popover.menu{PAD} separator {{ min-height: 10px; background: {img('menuitem-separator')} repeat-x center; margin: 0; }}",
                f"popover.menu{PAD} arrow.right {{ -gtk-icon-source: {img('menuitem-right-normal')}; }}",
                f"popovermenubar{PAD} {{ {bimg(pics, 'menubar-normal')} padding: 0; background-color: {face}; }}",
                f"popovermenubar{PAD} > item {{ padding: 3px 8px; color: @theme_fg_color_breeze; border-radius: 0; "
                "background: none; box-shadow: none; }",
                f"popovermenubar{PAD} > item:hover, popovermenubar{PAD} > item:selected {{ background-color: "
                f"{css_rgb(ACCENTS_CUR['accent'])}; color: #ffffff; }}"]
    # the tool tip is a window of its own, and GTK draws only a window node's background, not its border image: the
    # Kvantum picture is a one-pixel outline round the tool tip's face, so the same in plain colours
    tip = "tooltip"
    css += [f"{tip}{PAD}, {tip}{PAD}.background {{ background-color: {css_rgb(TOOLTIP)}; background-image: none; "
            f"border: 1px solid {css_rgb(OUTLINE)}; border-radius: 0; box-shadow: none; padding: 3px 5px; "
            "color: @tooltip_text_breeze; }",
            f"{tip}{PAD} > box > label, {tip}{PAD} > label {{ color: @tooltip_text_breeze; }}"]
    # frames around lists and text views; group boxes (GtkFrame) as an engraved line
    css += [f"scrolledwindow{PAD} > frame > border, frame{PAD}.view > border, scrolledwindow.frame{PAD} {{ "
            f"{bimg(pics, 'common-normal', fill=False)} }}" if gtk == 4 else
            f"scrolledwindow{PAD}.frame, frame{PAD} > border.view {{ {bimg(pics, 'common-normal', fill=False)} }}",
            f"frame{PAD} > border {{ {bimg(pics, 'group-normal', fill=False)} }}" if gtk == 3 else
            f"frame{PAD}:not(.view) {{ {bimg(pics, 'group-normal', fill=False)} }}",
            f"frame{PAD}.flat > border {{ border-image: none; }}" if gtk == 3 else f"frame{PAD}.flat {{ border-image: none; }}"]
    # tree expanders: the disclosure triangles
    exp = "treeview.view.expander, treeview.view expander" if gtk == 3 else "treeview.view.expander, treeexpander > expander, expander-widget > box > title > expander, expander"
    for state, pseudo in (("normal", ""), ("focused", ":hover"), ("disabled", ":disabled")):
        css.append(f"{', '.join(s + PAD + pseudo for s in exp.split(', '))} {{ -gtk-icon-source: {img('disclosure-plus-' + state)}; "
                   "min-width: 10px; min-height: 10px; color: transparent; }")
        css.append(f"{', '.join(s + PAD + ':checked' + pseudo for s in exp.split(', '))} {{ -gtk-icon-source: "
                   f"{img('disclosure-minus-' + state)}; }}")
    # selections: the accent's light form, black text, as Kvantum's item views
    light = css_rgb(ACCENTS_CUR["light"])
    css += [f"treeview.view{PAD}:selected, row{PAD}:selected, .view{PAD}:selected, columnview > listview > row{PAD}:selected "
            f"{{ background-color: {light}; color: #000000; }}"]
    css += [f"toolbar{PAD} {{ {bimg(pics, 'toolbar-normal')} padding: 2px; background-color: {face}; }}"]
    return "\n".join(css) + "\n"


ACCENTS_CUR = {}
INACTIVE_CUR = ["#505050"]


def css_rgb(c):
    return "#%02x%02x%02x" % tuple(c)


# ---------------------------------------------------------------- GTK 2
def scheme_colours(path):
    s = configparser.ConfigParser(interpolation=None)
    s.optionxform = str
    s.read(path)

    def c(group, key):
        return css_rgb(tuple(int(v) for v in s[group][key].split(",")[:3]))
    return {"bg": c("Colors:Window", "BackgroundNormal"), "fg": c("Colors:Window", "ForegroundNormal"),
            "base": c("Colors:View", "BackgroundNormal"), "text": c("Colors:View", "ForegroundNormal"),
            "sel": c("Colors:Selection", "BackgroundNormal"), "selfg": c("Colors:Selection", "ForegroundNormal"),
            "inactive": c("Colors:Window", "ForegroundInactive"), "tip": c("Colors:Tooltip", "BackgroundNormal"),
            "tipfg": c("Colors:Tooltip", "ForegroundNormal")}


GTK2_STATES = {"normal": "NORMAL", "focused": "PRELIGHT", "pressed": "ACTIVE", "disabled": "INSENSITIVE"}


def g2image(function, picture, pics, extra="", stretch=True, overlay=None, state=None, shadow=None):
    lines = ["\t\timage {", f"\t\t\tfunction = {function}"]
    if state:
        lines.append(f"\t\t\tstate = {state}")
    if shadow:
        lines.append(f"\t\t\tshadow = {shadow}")
    lines += [f"\t\t\t{x}" for x in extra.split(";") if x.strip()]
    if picture and not stretch:
        # a single picture (a check, an arrow): GTK 2's pixmap engine tiles a file that is not stretched, so it is the
        # overlay, drawn once at its own size in the middle of the box
        lines += [f'\t\t\toverlay_file = "../assets/{picture}.png"', "\t\t\toverlay_stretch = FALSE"]
    elif picture:
        lines.append(f'\t\t\tfile = "../assets/{picture}.png"')
        f = pics[picture][1]
        if f:
            t, b, l, r = f
            lines.append(f"\t\t\tborder = {{ {l}, {r}, {t}, {b} }}")
        lines.append("\t\t\tstretch = TRUE")
    if overlay:
        lines += [f'\t\t\toverlay_file = "../assets/{overlay}.png"', "\t\t\toverlay_stretch = FALSE"]
    lines.append("\t\t}")
    return lines


def gtkrc(pics, together, colours, name):
    k = colours
    out = [f"# {name} for GTK 2: Kubabbar Glass 9's classic controls on GTK 2's pixmap engine (gtk2-engines-pixbuf),",
           "# the pictures of its Kvantum theme (tools/make_gtk9.py). GPL-3.0-only.", "",
           'gtk-color-scheme = "bg_color:%s\\nfg_color:%s\\nbase_color:%s\\ntext_color:%s\\nselected_bg_color:%s\\n'
           'selected_fg_color:%s\\ntooltip_bg_color:%s\\ntooltip_fg_color:%s"' % (
               k["bg"], k["fg"], k["base"], k["text"], k["sel"], k["selfg"], k["tip"], k["tipfg"]),
           "gtk-button-images = 1", "gtk-menu-images = 1", "",
           'style "kg9-default" {',
           "\tGtkWidget::focus-line-width = 1", "\tGtkWidget::focus-padding = 0", "\tGtkWidget::interior-focus = 1",
           "\tGtkButton::default-border = { 2, 2, 2, 2 }", "\tGtkButton::default-outside-border = { 0, 0, 0, 0 }",
           "\tGtkButton::inner-border = { 4, 4, 1, 1 }", "\tGtkButton::child-displacement-x = 0",
           "\tGtkButton::child-displacement-y = 0",
           "\tGtkCheckButton::indicator-size = 13", "\tGtkCheckButton::indicator-spacing = 3",
           "\tGtkRange::slider-width = 16", "\tGtkRange::stepper-size = 16", "\tGtkRange::trough-border = 0",
           "\tGtkRange::stepper-spacing = 0", "\tGtkRange::trough-under-steppers = 0",
           "\tGtkScrollbar::min-slider-length = 28",
           f"\tGtkScrollbar::has-backward-stepper = {0 if together else 1}", "\tGtkScrollbar::has-forward-stepper = 1",
           f"\tGtkScrollbar::has-secondary-backward-stepper = {1 if together else 0}",
           "\tGtkScrollbar::has-secondary-forward-stepper = 0",
           "\tGtkScale::slider-length = 16", "\tGtkScale::slider-width = 16",
           "\tGtkNotebook::tab-overlap = 1", "\tGtkNotebook::tab-curvature = 0",
           "\tGtkMenuBar::internal-padding = 0", "\tGtkMenuBar::shadow-type = GTK_SHADOW_OUT",
           "\tGtkMenu::horizontal-padding = 0", "\tGtkMenu::vertical-padding = 1",
           "\tGtkMenuItem::arrow-scaling = 1.0", "\tGtkTreeView::expander-size = 10",
           "\tGtkExpander::expander-size = 10", "\tGtkToolbar::shadow-type = GTK_SHADOW_OUT",
           "\tGtkEntry::inner-border = { 4, 4, 3, 3 }", "\tGtkEntry::progress-border = { 0, 0, 0, 0 }",
           "\tGtkProgressBar::min-horizontal-bar-height = 12", "\tGtkProgressBar::xspacing = 0",
           "\tGtkProgressBar::yspacing = 0",
           "\txthickness = 2", "\tythickness = 2",
           '\tbg[NORMAL] = @bg_color', '\tbg[PRELIGHT] = @bg_color', '\tbg[ACTIVE] = "#cccccc"',
           '\tbg[SELECTED] = @selected_bg_color', '\tbg[INSENSITIVE] = @bg_color',
           '\tfg[NORMAL] = @fg_color', '\tfg[PRELIGHT] = @fg_color', '\tfg[ACTIVE] = @fg_color',
           '\tfg[SELECTED] = @selected_fg_color', f'\tfg[INSENSITIVE] = "{k["inactive"]}"',
           '\tbase[NORMAL] = @base_color', '\tbase[PRELIGHT] = @base_color', '\tbase[ACTIVE] = @selected_bg_color',
           '\tbase[SELECTED] = @selected_bg_color', '\tbase[INSENSITIVE] = "#f6f6f6"',
           '\ttext[NORMAL] = @text_color', '\ttext[PRELIGHT] = @text_color', '\ttext[ACTIVE] = @selected_fg_color',
           '\ttext[SELECTED] = @selected_fg_color', f'\ttext[INSENSITIVE] = "{k["inactive"]}"',
           '\tengine "pixmap" {']
    for state, gs in GTK2_STATES.items():
        out += g2image("BOX", f"button-default-{state}", pics, 'detail = "buttondefault"', state=gs)
    for state, gs in GTK2_STATES.items():
        out += g2image("BOX", f"button-{state}", pics, 'detail = "button"', state=gs, shadow="OUT")
        out += g2image("BOX", f"button-{'pressed' if state != 'disabled' else 'disabled'}", pics, 'detail = "button"',
                       state=gs, shadow="IN")
    # check boxes and radio buttons
    for state, gs in GTK2_STATES.items():
        out += g2image("CHECK", f"checkbox-checked-{state}", pics, "", state=gs, shadow="IN", stretch=False)
        out += g2image("CHECK", f"checkbox-{state}", pics, "", state=gs, shadow="OUT", stretch=False)
        out += g2image("CHECK", f"checkbox-tristate-{state}", pics, "", state=gs, shadow="ETCHED_IN", stretch=False)
        out += g2image("OPTION", f"radio-checked-{state}", pics, "", state=gs, shadow="IN", stretch=False)
        out += g2image("OPTION", f"radio-{state}", pics, "", state=gs, shadow="OUT", stretch=False)
    # text fields and frames
    out += g2image("SHADOW", "lineedit-disabled", pics, 'detail = "entry"', state="INSENSITIVE")
    out += g2image("SHADOW", "lineedit-normal", pics, 'detail = "entry"')
    out += g2image("FLAT_BOX", None, pics, 'detail = "entry_bg"')
    out += g2image("SHADOW", "common-normal", pics, 'detail = "scrolled_window"')
    out += g2image("SHADOW", "group-normal", pics, 'detail = "frame"')
    # spin buttons
    for state, gs in GTK2_STATES.items():
        for d in ("up", "down"):
            out += g2image("BOX", f"spin-{state}", pics, f'detail = "spinbutton_{d}"', state=gs,
                           overlay=f"arrow-{d}-{state}")
    out += g2image("ARROW", None, pics, 'detail = "spinbutton"')
    # scroll bars: the track, the scroll box with its grip, the arrow boxes
    out += g2image("BOX", "sgroove-normal", pics, 'detail = "trough"; orientation = VERTICAL')
    out += g2image("BOX", "sgroove-h-normal", pics, 'detail = "trough"; orientation = HORIZONTAL')
    for state, gs in GTK2_STATES.items():
        out += g2image("SLIDER", f"scrollbarslider-{state}", pics, 'detail = "slider"; orientation = VERTICAL', state=gs,
                       overlay=f"grip-{state}")
        out += g2image("SLIDER", f"scrollbarslider-{state}", pics, 'detail = "slider"; orientation = HORIZONTAL',
                       state=gs, overlay=f"grip-h-{state}")
    for d, arrow in (("up", "UP"), ("down", "DOWN"), ("left", "LEFT"), ("right", "RIGHT")):
        for state, gs in GTK2_STATES.items():
            out += g2image("STEPPER", f"sarrowbox-{d}-{state}", pics, f"arrow_direction = {arrow}", state=gs,
                           stretch=False)
    out += g2image("BOX", None, pics, 'detail = "vscrollbar"')
    out += g2image("BOX", None, pics, 'detail = "hscrollbar"')
    out += g2image("ARROW", None, pics, 'detail = "vscrollbar"')
    out += g2image("ARROW", None, pics, 'detail = "hscrollbar"')
    # sliders and progress bars
    out += g2image("BOX", "slider-normal", pics, 'detail = "trough"')
    for state, gs in GTK2_STATES.items():
        out += g2image("SLIDER", f"slidercursor-{state}", pics, 'detail = "hscale"', state=gs, stretch=False)
        out += g2image("SLIDER", f"slidercursor-{state}", pics, 'detail = "vscale"', state=gs, stretch=False)
    out += g2image("BOX", "progress-pattern-normal", pics, 'detail = "bar"')
    # tabs and their page
    for state, gs in (("toggled", "NORMAL"), ("normal", "ACTIVE")):
        out += g2image("EXTENSION", f"tab-{state}", pics, "gap_side = BOTTOM", state=gs)
    out += g2image("BOX_GAP", "tabframe-normal", pics, 'detail = "notebook"; gap_side = TOP')
    out += g2image("BOX", "tabframe-normal", pics, 'detail = "notebook"')
    # menus, the menu bar, items, separators, tool tips, tool bars, the disclosure triangles, combo arrows
    out += g2image("BOX", "menu-normal", pics, 'detail = "menu"')
    out += g2image("BOX", "menubar-normal", pics, 'detail = "menubar"')
    out += g2image("BOX", None, pics, 'detail = "menuitem"', state="NORMAL")
    out += g2image("HLINE", "menuitem-separator", pics, 'detail = "menuitem"')
    out += g2image("ARROW", "menuitem-right-focused", pics, 'detail = "menuitem"; state = PRELIGHT', stretch=False)
    out += g2image("ARROW", "menuitem-right-normal", pics, 'detail = "menuitem"', stretch=False)
    out += g2image("FLAT_BOX", "tooltip-normal", pics, 'detail = "tooltip"')
    out += g2image("BOX", "toolbar-normal", pics, 'detail = "toolbar"')
    out += g2image("BOX", "toolbar-normal", pics, 'detail = "handlebox_bin"')
    out += g2image("EXPANDER", "disclosure-minus-normal", pics, "expander_style = EXPANDED", stretch=False)
    out += g2image("EXPANDER", "disclosure-plus-normal", pics, "expander_style = COLLAPSED", stretch=False)
    out += g2image("EXPANDER", "disclosure-plus-normal", pics, "expander_style = SEMI_COLLAPSED", stretch=False)
    out += g2image("EXPANDER", "disclosure-minus-normal", pics, "expander_style = SEMI_EXPANDED", stretch=False)
    for d, arrow in (("down", "DOWN"), ("up", "UP"), ("left", "LEFT"), ("right", "RIGHT")):
        out += g2image("ARROW", f"arrow-{d}-normal", pics, f"arrow_direction = {arrow}", stretch=False)
    out += ["\t}", "}", ""]
    # menu items: the accent with white text; combo boxes and option menus; tree view headers; tool bar buttons
    accent = css_rgb(ACCENTS_CUR["accent"])
    out += ['style "kg9-menuitem" {', "\txthickness = 2", "\tythickness = 3",
            f'\tbg[PRELIGHT] = "{accent}"', '\tfg[PRELIGHT] = "#ffffff"', '\ttext[PRELIGHT] = "#ffffff"',
            '\tengine "pixmap" {', "\t\timage {", "\t\t\tfunction = BOX", '\t\t\tdetail = "menuitem"',
            "\t\t\tstate = PRELIGHT", '\t\t\tfile = "../assets/menuitem-bg.png"', "\t\t\tstretch = TRUE", "\t\t}",
            "\t}", "}", "",
            'style "kg9-menubar-item" = "kg9-menuitem" { xthickness = 6 ythickness = 3 }', "",
            'style "kg9-combo" {', "\txthickness = 3", "\tythickness = 3", '\tengine "pixmap" {']
    for state, gs in GTK2_STATES.items():
        out += g2image("BOX", f"combo-{state}", pics, 'detail = "button"', state=gs)
    out += g2image("ARROW", "popuparrow-normal", pics, "", stretch=False)
    out += g2image("VLINE", None, pics, "")
    out += ["\t}", "}", "", 'style "kg9-header" {', "\txthickness = 1", "\tythickness = 1", '\tengine "pixmap" {']
    for state, gs in (("normal", "NORMAL"), ("focused", "PRELIGHT"), ("pressed", "ACTIVE")):
        out += g2image("BOX", f"header-{state}", pics, 'detail = "button"', state=gs)
    out += ["\t}", "}", "", 'style "kg9-toolbutton" {', '\tengine "pixmap" {']
    out += g2image("BOX", None, pics, 'detail = "button"; state = NORMAL; shadow = NONE')
    for state, gs in (("focused", "PRELIGHT"), ("pressed", "ACTIVE")):
        out += g2image("BOX", f"tbutton-{state}", pics, 'detail = "button"', state=gs)
    out += ["\t}", "}", "", 'style "kg9-tooltip" {', "\txthickness = 4", "\tythickness = 4",
            '\tbg[NORMAL] = @tooltip_bg_color', '\tfg[NORMAL] = @tooltip_fg_color', "}", "",
            'class "GtkWidget" style "kg9-default"',
            'widget_class "*<GtkMenuItem>*" style "kg9-menuitem"',
            'widget_class "*<GtkMenuBar>.<GtkMenuItem>*" style "kg9-menubar-item"',
            'widget_class "*<GtkComboBox>.<GtkButton>" style "kg9-combo"',
            'widget_class "*<GtkComboBox>.<GtkToggleButton>" style "kg9-combo"',
            'widget_class "*<GtkComboBoxEntry>*<GtkButton>" style "kg9-combo"',
            'widget_class "*<GtkTreeView>*<GtkButton>" style "kg9-header"',
            'widget_class "*<GtkToolbar>*<GtkButton>" style "kg9-toolbutton"',
            'widget "gtk-tooltip*" style "kg9-tooltip"', ""]
    return "\n".join(out)


# ---------------------------------------------------------------- the themes
INDEX = """[Desktop Entry]
Type=X-GNOME-Metatheme
Name={name}
Comment=Kubabbar Glass 9: classic bevelled controls for GTK 2, GTK 3 and GTK 4 ({accent}; scroll arrows {arrows})
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme={name}
IconTheme=kubabbar-glass-stereo
"""


def write_theme(accent):
    ACCENTS_CUR.clear()
    ACCENTS_CUR.update(ACCENTS[accent])
    pics = pictures(accent)
    scheme = ROOT / "share/color-schemes" / f"{scheme_id(accent)}.colors"
    INACTIVE_CUR[0] = scheme_colours(scheme)["inactive"]
    base = THEMES / gtk_name(accent)
    if base.exists():
        shutil.rmtree(base)
    (base / "assets").mkdir(parents=True)
    for name, (arr, _) in sorted(pics.items()):
        png(arr, base / "assets" / f"{name}.png")
    bg = np.zeros((2, 2, 4))
    bg[...] = (*ACCENTS[accent]["accent"], 1.0)
    png(bg, base / "assets" / "menuitem-bg.png")
    for gtk in ("3.0", "4.0"):
        d = base / f"gtk-{gtk}"
        d.mkdir()
        breeze = f"/usr/share/themes/Breeze/gtk-{gtk}/gtk.css"
        colours = subprocess.run([sys.executable, str(HERE / "kde2gtk_colors.py"), str(scheme), breeze],
                                 check=True, capture_output=True, text=True).stdout
        (d / "colors.css").write_text(colours)
        (d / "gtk.css").write_text(
            "/* SPDX-License-Identifier: GPL-3.0-only */\n"
            f"/* {gtk_name(accent)}: the Breeze GTK shapes (breeze-gtk, LGPL-2.1+, The KDE Developers) in the scheme's colours,\n"
            "   with Kubabbar Glass 9's classic controls over them, the pictures of its Kvantum theme. */\n"
            f'@import url("file://{breeze}");\n@import url("colors.css");\n@import url("classic.css");\n')
        (d / "classic.css").write_text(classic_css(pics, True, int(gtk[0])))
    (base / "gtk-2.0").mkdir()
    (base / "gtk-2.0" / "gtkrc").write_text(gtkrc(pics, True, scheme_colours(scheme), gtk_name(accent)))
    (base / "index.theme").write_text(INDEX.format(name=gtk_name(accent), accent=accent, arrows="together at the end"))
    # the Apart theme: the same theme, the scroll arrows at both ends (GTK 2 and GTK 3; GTK 4 has none)
    apart = THEMES / gtk_name(accent, False)
    if apart.exists():
        shutil.rmtree(apart)
    for gtk in ("2.0", "3.0", "4.0"):
        (apart / f"gtk-{gtk}").mkdir(parents=True)
    (apart / "gtk-3.0" / "gtk.css").write_text(
        "/* SPDX-License-Identifier: GPL-3.0-only */\n"
        f'@import url("../../{gtk_name(accent)}/gtk-3.0/gtk.css");\n'
        f"scrollbar{PAD} {{ -GtkScrollbar-has-backward-stepper: true; -GtkScrollbar-has-forward-stepper: true; "
        "-GtkScrollbar-has-secondary-backward-stepper: false; -GtkScrollbar-has-secondary-forward-stepper: false; }\n")
    (apart / "gtk-4.0" / "gtk.css").write_text(
        "/* SPDX-License-Identifier: GPL-3.0-only */\n"
        "/* GTK 4 has no scroll arrows: the same drawing as the theme the arrows are together in. */\n"
        f'@import url("../../{gtk_name(accent)}/gtk-4.0/gtk.css");\n')
    (apart / "gtk-2.0" / "gtkrc").write_text(
        f"# {gtk_name(accent, False)} for GTK 2: {gtk_name(accent)} with the scroll arrows at both ends. GPL-3.0-only.\n"
        f'include "../../{gtk_name(accent)}/gtk-2.0/gtkrc"\n'
        'style "kg9-apart" {\n\tGtkScrollbar::has-backward-stepper = 1\n\tGtkScrollbar::has-forward-stepper = 1\n'
        "\tGtkScrollbar::has-secondary-backward-stepper = 0\n\tGtkScrollbar::has-secondary-forward-stepper = 0\n}\n"
        'class "GtkScrollbar" style "kg9-apart"\n')
    (apart / "index.theme").write_text(INDEX.format(name=gtk_name(accent, False), accent=accent, arrows="at both ends"))
    print("wrote", gtk_name(accent), gtk_name(accent, False), len(pics), "pictures")


def share_pictures():
    """A picture an accent's theme has byte for byte like the default theme's is a link to the default's copy: only the
    pictures the accent colours stay files of their own."""
    default = THEMES / gtk_name(DEFAULT_ACCENT) / "assets"
    linked = 0
    for accent in ACCENTS:
        if accent == DEFAULT_ACCENT:
            continue
        for pic in sorted((THEMES / gtk_name(accent) / "assets").iterdir()):
            twin = default / pic.name
            if not pic.is_symlink() and twin.exists() and twin.read_bytes() == pic.read_bytes():
                pic.unlink()
                pic.symlink_to(f"../../{gtk_name(DEFAULT_ACCENT)}/assets/{pic.name}")
                linked += 1
    print("linked", linked, "pictures to the default theme's")


def main():
    accents = sys.argv[1:] or list(ACCENTS)
    for accent in accents:
        write_theme(accent)
    if not sys.argv[1:]:
        share_pictures()


if __name__ == "__main__":
    main()
