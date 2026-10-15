#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Write GTK colors.css for the Breeze GTK theme from a KDE colour scheme.

The names are the *_breeze colours that breeze-gtk defines; kde-gtk-config fills the
same names from the active KDE scheme, so a theme built with this file looks the same
whether or not kde-gtk-config is running.
"""
import configparser
import sys


def load(path):
    scheme = configparser.ConfigParser(interpolation=None)
    scheme.optionxform = str
    scheme.read(path)
    return scheme


def rgb(scheme, group, key):
    return tuple(int(v) for v in scheme[group][key].split(",")[:3])


def css(c, alpha=None):
    return "rgba(%d, %d, %d, %s)" % (*c, alpha) if alpha is not None else "#%02x%02x%02x" % c


def mix(a, b, amount):
    return tuple(round(x + (y - x) * amount) for x, y in zip(a, b))


def colors(s):
    fg, text = rgb(s, "Colors:Window", "ForegroundNormal"), rgb(s, "Colors:View", "ForegroundNormal")
    bg, base = rgb(s, "Colors:Window", "BackgroundNormal"), rgb(s, "Colors:View", "BackgroundNormal")
    sel, self_ = rgb(s, "Colors:Selection", "BackgroundNormal"), rgb(s, "Colors:Selection", "ForegroundNormal")
    sel_hover = rgb(s, "Colors:Selection", "DecorationHover")
    hover, focus = rgb(s, "Colors:View", "DecorationHover"), rgb(s, "Colors:View", "DecorationFocus")
    btn, btn_fg = rgb(s, "Colors:Button", "BackgroundNormal"), rgb(s, "Colors:Button", "ForegroundNormal")
    btn_hover, btn_focus = rgb(s, "Colors:Button", "DecorationHover"), rgb(s, "Colors:Button", "DecorationFocus")
    tip, tip_fg = rgb(s, "Colors:Tooltip", "BackgroundNormal"), rgb(s, "Colors:Tooltip", "ForegroundNormal")
    wm_a, wm_af = rgb(s, "WM", "activeBackground"), rgb(s, "WM", "activeForeground")
    wm_i, wm_if = rgb(s, "WM", "inactiveBackground"), rgb(s, "WM", "inactiveForeground")
    inactive_text = rgb(s, "Colors:Window", "ForegroundInactive")
    ins_bg = mix(bg, fg, 0.07)
    ins_base_fg = mix(base, fg, 0.1)
    borders = mix(bg, fg, 0.2)
    d = {}
    d["theme_fg_color"], d["theme_text_color"], d["theme_bg_color"], d["theme_base_color"] = css(fg), css(text), css(bg), css(base)
    d["theme_view_hover_decoration_color"], d["theme_hovering_selected_bg_color"] = css(hover), css(sel_hover)
    d["theme_selected_bg_color"], d["theme_selected_fg_color"], d["theme_view_active_decoration_color"] = css(sel), css(self_), css(hover)
    d["insensitive_selected_bg_color"] = css(sel, 0.35)
    d["insensitive_bg_color"], d["insensitive_fg_color"] = css(ins_bg), css(fg, 0.35)
    d["insensitive_base_color"], d["insensitive_base_fg_color"] = css(text, 0.35), css(ins_base_fg)
    d["insensitive_selected_fg_color"] = css(ins_base_fg)
    d["theme_unfocused_fg_color"], d["theme_unfocused_text_color"] = css(fg), css(text)
    d["theme_unfocused_bg_color"], d["theme_unfocused_base_color"] = css(bg), css(base)
    d["theme_unfocused_selected_bg_color_alt"], d["theme_unfocused_selected_bg_color"] = css(sel), css(sel, 0.5)
    d["theme_unfocused_selected_fg_color"] = css(fg)
    d["insensitive_unfocused_selected_bg_color"], d["insensitive_unfocused_fg_color"] = css(sel, 0.35), css(fg, 0.35)
    d["insensitive_unfocused_bg_color"], d["insensitive_unfocused_selected_fg_color"] = css(ins_bg), css(ins_base_fg)
    d["theme_unfocused_view_text_color"], d["theme_unfocused_view_bg_color"] = css(text, 0.35), css(base)
    d["borders"], d["unfocused_borders"] = css(borders), css(borders)
    d["insensitive_borders"] = d["unfocused_insensitive_borders"] = css(borders, 0.35)
    for state in ("", "_backdrop"):
        d["theme_button_background_normal" if not state else "theme_button_background_backdrop"] = css(btn)
        d["theme_button_decoration_hover" + state], d["theme_button_decoration_focus" + state] = css(btn_hover), css(btn_focus)
        d["theme_button_foreground_normal" if not state else "theme_button_foreground_backdrop"] = css(btn_fg)
        d["theme_button_foreground_active" + state] = css(self_ if not state else btn_fg)
        ins = "theme_button_background_insensitive" if not state else "theme_button_background_backdrop_insensitive"
        d[ins] = css(mix(btn, fg, 0.1))
        d["theme_button_decoration_hover" + state + "_insensitive"] = css(btn_hover, 0.35)
        d["theme_button_decoration_focus" + state + "_insensitive"] = css(btn_focus, 0.35)
        d["theme_button_foreground_insensitive" if not state else "theme_button_foreground_backdrop_insensitive"] = css(btn_fg, 0.35)
        d["theme_button_foreground_active" + state + "_insensitive"] = css(ins_base_fg)
    for name, key in (("warning", "ForegroundNeutral"), ("error", "ForegroundNegative"), ("success", "ForegroundPositive")):
        c = rgb(s, "Colors:View", key)
        d[name + "_color"] = d[name + "_color_backdrop"] = css(c)
        d[name + "_color_insensitive"] = d[name + "_color_insensitive_backdrop"] = css(c, 0.35)
    d["link_color"], d["link_visited_color"] = css(rgb(s, "Colors:View", "ForegroundLink")), css(rgb(s, "Colors:View", "ForegroundVisited"))
    d["theme_titlebar_background"], d["theme_titlebar_foreground"], d["theme_titlebar_background_light"] = css(wm_a), css(wm_af), css(wm_a)
    d["theme_titlebar_foreground_backdrop"], d["theme_titlebar_background_backdrop"] = css(wm_if), css(wm_i)
    d["theme_titlebar_foreground_insensitive"] = css(wm_af, 0.35)
    d["theme_titlebar_foreground_insensitive_backdrop"] = css(wm_if, 0.35)
    d["tooltip_text"], d["tooltip_background"], d["tooltip_border"] = css(tip_fg), css(tip), css(mix(tip, tip_fg, 0.2))
    d["print_paper_backdrop"], d["content_view_bg"] = css(base), css(base)
    return d


def main(scheme_path, base_theme_css=None):
    d = colors(load(scheme_path))
    out = ["/* Generated by tools/kde2gtk_colors.py from %s. */" % scheme_path.rsplit("/", 1)[-1]]
    out += ["@define-color %s_breeze %s;" % (k, v) for k, v in d.items()]
    if base_theme_css:
        want = {line.split()[1][:-7] for line in open(base_theme_css) if line.startswith("@define-color ") and line.split()[1].endswith("_breeze")}
        missing = want - set(d)
        if missing:
            sys.exit("unmapped breeze colours: " + ", ".join(sorted(missing)))
    print("\n".join(out))


if __name__ == "__main__":
    main(*sys.argv[1:3])
