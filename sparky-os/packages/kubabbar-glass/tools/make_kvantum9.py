#!/usr/bin/env python3
"""Kubabbar Glass 9's Kvantum themes: every control drawn here, original, in the spirit of the classic Platinum
appearance (bevelled grey controls, a ringed default button, the gripped scroll box in the accent colour, the striped
progress bar, rounded tabs, disclosure triangles). One SVG per accent variation; for each accent two configurations,
the scroll arrows together at the end of the scrollbar (the default) and at both ends (the "Apart" theme, which links
the same SVG). The key scroll_arrows_together needs the edition's Kvantum (1.1.8-1+stereo3d1 or later).
Texts take the KDE colour scheme's palette: the configurations name no general colour. GPL-3.0-only."""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from platinum9 import (ACCENTS, ACCENT_NAMES, DARK, DEFAULT_ACCENT, DISABLED_LINE, FACE, FACE_ALT, LANGUAGES, LIGHT,  # noqa: E402
                       OUTLINE, PRESSED, SHADOW, TOOLTIP, TRACK, VIEW, hexa, kvantum_name)

ROOT = Path(__file__).resolve().parents[1] / "share/Kvantum"
SS = 4                      # subpixels per pixel and axis
STATES = ("normal", "focused", "pressed", "toggled", "disabled")


def mix(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


# ---------------------------------------------------------------- pixel art with supersampled coverage
class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgba = np.zeros((h, w, 4))          # premultiplied
        ys, xs = np.mgrid[0:h * SS, 0:w * SS]
        self.x = (xs + 0.5) / SS
        self.y = (ys + 0.5) / SS

    def rect(self, inset, radius=0.0, corners=(1, 1, 1, 1), box=None):
        """Subpixels inside the rectangle inset from the canvas (or box (l, t, r, b)), corners rounded by radius:
        corners = (top-left, top-right, bottom-right, bottom-left)."""
        l, t, r, b = box if box else (inset, inset, self.w - inset, self.h - inset)
        x, y = self.x, self.y
        inside = (x >= l) & (x < r) & (y >= t) & (y < b)
        rad = max(0.0, radius)
        if rad > 0:
            for on, cx, cy, sx, sy in ((corners[0], l + rad, t + rad, -1, -1), (corners[1], r - rad, t + rad, 1, -1),
                                       (corners[2], r - rad, b - rad, 1, 1), (corners[3], l + rad, b - rad, -1, 1)):
                if not on:
                    continue
                zone = ((x - cx) * sx > 0) & ((y - cy) * sy > 0)
                inside &= ~zone | ((x - cx) ** 2 + (y - cy) ** 2 <= rad * rad)
        return inside

    def side_light(self, inset):
        """Subpixels nearer the top or left edge than the bottom or right edge of the inset rectangle."""
        l, t, r, b = inset, inset, self.w - inset, self.h - inset
        return np.minimum(self.x - l, self.y - t) < np.minimum(r - self.x, b - self.y)

    def paint(self, mask, colour, alpha=1.0):
        cov = mask.reshape(self.h, SS, self.w, SS).mean(axis=(1, 3)) * alpha
        c = np.array([*(v / 255 for v in colour), 1.0])
        self.rgba = c * cov[..., None] + self.rgba * (1 - cov[..., None])

    def erase(self, mask):
        cov = mask.reshape(self.h, SS, self.w, SS).mean(axis=(1, 3))
        self.rgba = self.rgba * (1 - cov[..., None])

    def disc(self, cx, cy, r):
        return (self.x - cx) ** 2 + (self.y - cy) ** 2 <= r * r

    def line(self, pts, width):
        hit = np.zeros_like(self.x, dtype=bool)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            dx, dy = x1 - x0, y1 - y0
            tt = np.clip(((self.x - x0) * dx + (self.y - y0) * dy) / (dx * dx + dy * dy), 0, 1)
            hit |= (self.x - (x0 + tt * dx)) ** 2 + (self.y - (y0 + tt * dy)) ** 2 <= (width / 2) ** 2
        return hit

    def polygon(self, pts):
        """Even-odd fill of a polygon on the subpixel grid."""
        inside = np.zeros_like(self.x, dtype=bool)
        n = len(pts)
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            cond = ((y0 > self.y) != (y1 > self.y))
            xs = (x1 - x0) * (self.y - y0) / ((y1 - y0) if y1 != y0 else 1e-9) + x0
            inside ^= cond & (self.x < xs)
        return inside

    def array(self):
        a = self.rgba[..., 3]
        rgb = np.where(a[..., None] > 0, self.rgba[..., :3] / np.maximum(a[..., None], 1e-9), 0)
        return np.concatenate([np.round(rgb * 255), np.round(a[..., None] * 1000) / 1000], axis=2)


def bevel_box(w, h, inset, radius, outline, light, dark, face, corners=(1, 1, 1, 1), bevel=1, outline_w=1):
    c = Canvas(w, h)
    c.paint(c.rect(inset, radius, corners), outline)
    inner = c.rect(inset + outline_w, radius - outline_w, corners)
    lit = c.side_light(inset + outline_w)
    c.paint(inner & lit, light)
    c.paint(inner & ~lit, dark)
    c.paint(c.rect(inset + outline_w + bevel, radius - outline_w - bevel, corners), face)
    return c


def nine(prefix, arr, t, b, l, r):
    """Kvantum's frame parts ({prefix}-top ...) and the interior ({prefix})."""
    h, w = arr.shape[:2]
    parts = {"-topleft": arr[:t, :l], "-top": arr[:t, l:w - r], "-topright": arr[:t, w - r:],
             "-left": arr[t:h - b, :l], "": arr[t:h - b, l:w - r], "-right": arr[t:h - b, w - r:],
             "-bottomleft": arr[h - b:, :l], "-bottom": arr[h - b:, l:w - r], "-bottomright": arr[h - b:, w - r:]}
    return {prefix + k: v for k, v in parts.items() if v.size}


def transparent(w=1, h=1):
    return np.zeros((h, w, 4))


# ---------------------------------------------------------------- the elements
def elements(acc):
    A = ACCENTS[acc]
    out = {}

    def framed(name, f, make):
        t, b, l, r = f if isinstance(f, tuple) else (f, f, f, f)
        for state in STATES:
            arr = make(state)
            if arr is not None:
                out.update(nine(f"{name}-{state}", arr, t, b, l, r))

    # push button: two outer pixels for the default ring, a gap, then the outline, the bevel and the face
    def button(state):
        w = h = 14
        if state in ("pressed", "toggled"):
            return bevel_box(w, h, 3, 3, OUTLINE, (80, 80, 80), (130, 130, 130), PRESSED).array()
        if state == "disabled":
            return bevel_box(w, h, 3, 3, DISABLED_LINE, (242, 242, 242), (200, 200, 200), FACE).array()
        return bevel_box(w, h, 3, 3, OUTLINE, LIGHT, SHADOW, FACE).array()
    framed("button", 6, button)
    ring = Canvas(14, 14)
    ring.paint(ring.rect(0, 5) & ~ring.rect(2, 3), OUTLINE)
    ring.erase(ring.rect(6, 0))                     # the interior part stays empty
    out.update(nine("button-default", ring.array(), 6, 6, 6, 6))
    out["button-default"] = transparent()
    out["button-default-indicator"] = transparent(8, 8)

    # bevel buttons (tool buttons, toolbox tabs)
    def tbutton(state):
        if state == "pressed":
            return bevel_box(8, 8, 0, 1, (90, 90, 90), (110, 110, 110), (190, 190, 190), (150, 150, 150)).array()
        if state == "toggled":
            return bevel_box(8, 8, 0, 1, (90, 90, 90), (140, 140, 140), (226, 226, 226), (190, 190, 190)).array()
        if state == "focused":
            return bevel_box(8, 8, 0, 1, (90, 90, 90), LIGHT, SHADOW, (232, 232, 232)).array()
        if state == "disabled":
            return bevel_box(8, 8, 0, 1, (180, 180, 180), (242, 242, 242), (210, 210, 210), FACE).array()
        return bevel_box(8, 8, 0, 1, (90, 90, 90), LIGHT, SHADOW, FACE).array()
    framed("tbutton", 3, tbutton)

    # pop-up menus (combo boxes) and the little arrows (spin boxes)
    def combo(state):
        if state in ("pressed", "toggled"):
            return bevel_box(8, 8, 0, 3, OUTLINE, (130, 130, 130), (220, 220, 220), (184, 184, 184)).array()
        if state == "disabled":
            return bevel_box(8, 8, 0, 3, DISABLED_LINE, (242, 242, 242), (200, 200, 200), FACE).array()
        return bevel_box(8, 8, 0, 3, OUTLINE, LIGHT, SHADOW, FACE).array()
    framed("combo", 3, combo)

    def spin(state):
        if state in ("pressed", "toggled"):
            return bevel_box(6, 6, 0, 1, OUTLINE, (110, 110, 110), (190, 190, 190), (150, 150, 150)).array()
        if state == "disabled":
            return bevel_box(6, 6, 0, 1, DISABLED_LINE, (242, 242, 242), (210, 210, 210), FACE).array()
        return bevel_box(6, 6, 0, 1, OUTLINE, LIGHT, SHADOW, FACE).array()
    framed("spin", 2, spin)

    # text fields: a sunken edge and a dark line; the keyboard focus is a ring in the accent colour
    def sunken_field(state, face):
        c = Canvas(8, 8)
        if state == "focused":
            c.paint(c.rect(0), A["mid"])
        elif state == "disabled":
            band = c.rect(1) & ~c.rect(2)
            c.paint(band & c.side_light(1), (210, 210, 210))
            c.paint(band & ~c.side_light(1), (248, 248, 248))
        else:
            band = c.rect(1) & ~c.rect(2)
            c.paint(band & c.side_light(1), SHADOW)
            c.paint(band & ~c.side_light(1), LIGHT)
        c.paint(c.rect(2), DISABLED_LINE if state == "disabled" else OUTLINE)
        c.paint(c.rect(3), (246, 246, 246) if state == "disabled" else face)
        return c.array()
    framed("lineedit", 3, lambda s: sunken_field(s, VIEW))

    # frames around lists and text views
    def common(state):
        c = Canvas(6, 6)
        band = c.rect(0) & ~c.rect(1)
        c.paint(band & c.side_light(0), SHADOW)
        c.paint(band & ~c.side_light(0), LIGHT)
        c.paint(c.rect(1) & ~c.rect(2), DISABLED_LINE if state == "disabled" else OUTLINE)
        c.erase(c.rect(2))
        return c.array()
    framed("common", 2, common)

    # the keyboard focus outline (Kvantum's focus frame has no state)
    fc = Canvas(4, 4)
    fc.paint(fc.rect(0) & ~fc.rect(1), A["dark"], 0.85)
    for k, v in nine("focus", fc.array(), 1, 1, 1, 1).items():
        out[k] = v
    out["focus-top0"] = out["focus-top"]

    # group boxes: an engraved line
    def group(state):
        c = Canvas(6, 6)
        c.paint(c.rect(0) & ~c.rect(1), SHADOW)
        c.paint(c.rect(1) & ~c.rect(2), LIGHT)
        return c.array()
    framed("group", 2, group)

    # tabs: rounded top corners; the current tab is the face of its pane and open at the bottom
    def tab(state):
        c = Canvas(8, 9)
        corners = (1, 1, 0, 0)
        current = state in ("toggled", "pressed")
        face = FACE if current else (238, 238, 238) if state == "focused" else (200, 200, 200)
        line = DISABLED_LINE if state == "disabled" else OUTLINE
        c.paint(c.rect(0, 4, corners), line)
        inner = c.rect(0, 3, corners, box=(1, 1, 7, 9))
        lit = c.side_light(1)
        c.paint(inner & lit, LIGHT)
        c.paint(inner & ~lit, SHADOW if not current else FACE)
        c.paint(c.rect(0, 2, corners, box=(2, 2, 6, 9)), face)
        if current:
            c.paint(c.rect(0, box=(1, 8, 7, 9)), FACE)
        else:
            c.paint(c.rect(0, box=(0, 8, 8, 9)), line)
        return c.array()
    framed("tab", (4, 1, 3, 3), tab)
    for state in ("normal", "focused", "pressed", "disabled"):
        x = Canvas(12, 12)
        if state in ("focused", "pressed"):
            x.paint(x.rect(0, 2), FACE_ALT if state == "focused" else SHADOW)
        x.paint(x.line([(3.5, 3.5), (8.5, 8.5)], 1.6) | x.line([(8.5, 3.5), (3.5, 8.5)], 1.6),
                DISABLED_LINE if state == "disabled" else OUTLINE)
        out[f"tab-close-{state}"] = x.array()
    out["tab-tear"] = transparent(4, 4)

    def tabframe(state):
        return bevel_box(6, 6, 0, 0, DISABLED_LINE if state == "disabled" else OUTLINE, LIGHT, SHADOW, FACE).array()
    framed("tabframe", 2, tabframe)

    # list and table headers
    def header(state):
        face = {"pressed": (176, 176, 176), "toggled": (206, 206, 206)}.get(state, FACE)
        c = Canvas(4, 4)
        c.paint(c.rect(0), face)
        c.paint(c.rect(0, box=(0, 0, 4, 1)) | c.rect(0, box=(0, 0, 1, 4)), LIGHT if state != "pressed" else (150, 150, 150))
        c.paint(c.rect(0, box=(3, 0, 4, 4)) | c.rect(0, box=(0, 3, 4, 4)), (136, 136, 136))
        return c.array()
    framed("header", 1, header)
    out["header-separator"] = transparent(1, 8)

    # toolbars and their handle and separators
    def toolbar(state):
        c = Canvas(4, 4)
        c.paint(c.rect(0), FACE)
        c.paint(c.rect(0, box=(0, 0, 4, 1)) | c.rect(0, box=(0, 0, 1, 4)), LIGHT)
        c.paint(c.rect(0, box=(0, 3, 4, 4)) | c.rect(0, box=(3, 0, 4, 4)), SHADOW)
        return c.array()
    framed("toolbar", 1, toolbar)
    hd = Canvas(6, 12)
    for yy in range(1, 12, 3):
        hd.paint(hd.rect(0, box=(1, yy, 4, yy + 1)), SHADOW)
        hd.paint(hd.rect(0, box=(2, yy + 1, 5, yy + 2)), LIGHT)
    out["toolbar-handle"] = out["toolbar-handle0"] = hd.array()
    sp = Canvas(2, 12)
    sp.paint(sp.rect(0, box=(0, 0, 1, 12)), SHADOW)
    sp.paint(sp.rect(0, box=(1, 0, 2, 12)), LIGHT)
    out["toolbar-separator"] = sp.array()

    # pinstripes: dock titles and inner (MDI) title bars
    def stripes(active):
        c = Canvas(2, 16)
        c.paint(c.rect(0), FACE)
        if active:
            for yy in range(3, 13, 2):
                c.paint(c.rect(0, box=(0, yy, 2, yy + 1)), (170, 170, 170))
                c.paint(c.rect(0, box=(0, yy + 1, 2, yy + 2)), LIGHT)
        return c.array()
    out["dock-normal"] = stripes(False)
    out["dock-focused"] = stripes(True)
    out["titlebar-normal"] = stripes(False)
    out["titlebar-focused"] = stripes(True)

    def mdi(kind, state):
        c = bevel_box(12, 12, 0, 1, DISABLED_LINE if state == "disabled" else OUTLINE,
                      (110, 110, 110) if state == "pressed" else LIGHT,
                      (190, 190, 190) if state == "pressed" else SHADOW,
                      (150, 150, 150) if state == "pressed" else FACE)
        ink = DISABLED_LINE if state == "disabled" else OUTLINE
        if kind == "maximize":
            c.paint(c.rect(0, box=(3, 3, 9, 9)) & ~c.rect(0, box=(4, 4, 8, 8)), ink)
        elif kind == "restore":
            c.paint(c.rect(0, box=(3, 5, 8, 10)) & ~c.rect(0, box=(4, 6, 7, 9)), ink)
            c.paint(c.rect(0, box=(5, 2, 10, 3)) | c.rect(0, box=(9, 2, 10, 7)), ink)
        elif kind == "minimize":
            c.paint(c.rect(0, box=(3, 8, 9, 9)), ink)
        elif kind == "shade":
            c.paint(c.rect(0, box=(3, 3, 9, 4)), ink)
        elif kind == "menu":
            for yy in (3, 6, 9):
                c.paint(c.rect(0, box=(3, yy, 9, yy + 1)), ink)
        return c.array()
    for kind in ("close", "maximize", "minimize", "restore", "shade", "menu"):
        for state in ("normal", "focused", "pressed", "disabled"):
            out[f"mdi-{kind}-{state}"] = mdi(kind, state)

    # splitters and the size grip
    for state in ("normal", "focused", "pressed"):
        out[f"splitter-{state}"] = transparent(2, 2)
        g = Canvas(4, 16)
        for yy in range(1, 16, 3):
            g.paint(g.rect(0, box=(1, yy, 2, yy + 1)), SHADOW)
            g.paint(g.rect(0, box=(2, yy + 1, 3, yy + 2)), LIGHT)
        out[f"splitter-grip-{state}"] = g.array()
    for state in ("normal", "focused"):
        g = Canvas(12, 12)
        for k in (4, 7, 10):
            g.paint(g.line([(k, 11.5), (11.5, k)], 1.0), SHADOW)
            g.paint(g.line([(k + 1, 11.5), (11.5, k + 1)], 1.0), LIGHT)
        out[f"sizegrip-{state}"] = g.array()

    # sliders: a sunken channel and a bevelled handle with an accent centre
    def channel(state):
        c = Canvas(6, 6)
        band = c.rect(0) & ~c.rect(1)
        c.paint(band & c.side_light(0), DARK if state != "disabled" else (200, 200, 200))
        c.paint(band & ~c.side_light(0), LIGHT)
        c.paint(c.rect(1), DISABLED_LINE if state == "disabled" else OUTLINE)
        c.paint(c.rect(2), VIEW if state != "disabled" else (246, 246, 246))
        return c.array()
    framed("slider", 2, channel)
    out["slider-topglow-normal"] = out["slider-bottomglow-normal"] = out["slider-tick-normal"] = transparent(2, 2)
    for state in ("normal", "focused", "pressed", "disabled"):
        if state == "pressed":
            c = bevel_box(16, 16, 0, 3, OUTLINE, (110, 110, 110), (200, 200, 200), (176, 176, 176))
        elif state == "disabled":
            c = bevel_box(16, 16, 0, 3, DISABLED_LINE, (242, 242, 242), (210, 210, 210), FACE)
        else:
            c = bevel_box(16, 16, 0, 3, OUTLINE, LIGHT, SHADOW, FACE)
        c.paint(c.rect(0, 1.5, box=(6, 6, 10, 10)), A["mid"] if state != "disabled" else (205, 205, 205))
        out[f"slidercursor-{state}"] = c.array()

    # progress bars: a sunken track, contents in the accent with a lighter upper band
    def track(state):
        c = Canvas(6, 6)
        c.paint(c.rect(0), DISABLED_LINE if state == "disabled" else OUTLINE)
        band = c.rect(1) & ~c.rect(2)
        c.paint(band & c.side_light(1), (150, 150, 150))
        c.paint(band & ~c.side_light(1), (246, 246, 246))
        c.paint(c.rect(2), (232, 232, 232))
        return c.array()
    framed("progress", 2, track)
    for state in ("normal", "focused", "toggled", "disabled"):
        base = A["accent"] if state != "disabled" else (160, 160, 160)
        c = Canvas(2, 12)
        rows = [mix(base, LIGHT, 0.62), mix(base, LIGHT, 0.42), mix(base, LIGHT, 0.30), mix(base, LIGHT, 0.20),
                mix(base, LIGHT, 0.12), base, base, base, base, mix(base, (0, 0, 0), 0.08), mix(base, (0, 0, 0), 0.16),
                mix(base, (0, 0, 0), 0.28)]
        for yy, col in enumerate(rows):
            c.paint(c.rect(0, box=(0, yy, 2, yy + 1)), col)
        out[f"progress-pattern-{state}"] = c.array()

    # list and tree selections: the highlight, light, for the active window; grey for an inactive one
    for state in STATES:
        c = Canvas(2, 2)
        if state == "pressed":
            c.paint(c.rect(0), A["light"])
        elif state == "toggled":
            c.paint(c.rect(0), (212, 212, 212))
        out[f"itemview-{state}"] = c.array()

    # scroll bars: the track and the scroll box in the accent colour with its grip (the arrow boxes are below)
    def groove(state):
        c = Canvas(8, 8)
        empty = state == "disabled"
        c.paint(c.rect(0), (238, 238, 238) if empty else TRACK)
        c.paint(c.rect(0, box=(0, 0, 1, 8)) | c.rect(0, box=(0, 0, 8, 1)), (205, 205, 205) if empty else DARK)
        c.paint(c.rect(0, box=(7, 0, 8, 8)), (250, 250, 250) if empty else (222, 222, 222))
        return c.array()
    framed("sgroove", 1, groove)
    # Kvantum asks for a "glow" above and below the scroll box under the track's interior name: present and empty
    for state in STATES:
        out[f"sgroove-topglow-{state}"] = out[f"sgroove-bottomglow-{state}"] = transparent()

    def thumb(state):
        if state == "disabled":
            return bevel_box(6, 6, 0, 0, (150, 150, 150), (242, 242, 242), (210, 210, 210), FACE).array()
        face = mix(A["light"], A["mid"], 0.5)
        if state in ("pressed", "toggled"):
            face = mix(A["mid"], A["accent"], 0.3)
        return bevel_box(6, 6, 0, 0, OUTLINE, mix(face, LIGHT, 0.6), mix(face, A["dark"], 0.45), face).array()
    framed("scrollbarslider", 2, thumb)
    for state in ("normal", "focused", "pressed", "disabled"):
        g = Canvas(8, 8)
        ink = A["dark"] if state != "disabled" else (170, 170, 170)
        for yy in (1, 3.5, 6):
            g.paint(g.rect(0, box=(1, yy, 7, yy + 1)), ink)
            g.paint(g.rect(0, box=(1, yy + 1, 7, yy + 2)) & ~g.rect(0, box=(1, yy, 7, yy + 1)), mix(A["light"], LIGHT, 0.5))
        out[f"grip-{state}"] = g.array()

    # arrows (solid when active), disclosure triangles, menu arrows
    def tri(direction, colour, size=10, fill=None):
        c = Canvas(size, size)
        m = size / 2
        a, b2 = size * 0.1, size * 0.9
        pts = {"up": [(a, b2 - 1.5), (b2, b2 - 1.5), (m, a + 0.5)], "down": [(a, a + 1.5), (b2, a + 1.5), (m, b2 - 0.5)],
               "left": [(b2 - 1.5, a), (b2 - 1.5, b2), (a + 0.5, m)], "right": [(a + 1.5, a), (a + 1.5, b2), (b2 - 0.5, m)]}[direction]
        shape = c.polygon(pts)
        c.paint(shape, colour)
        if fill:
            inner = c.polygon([(px + (m - px) * 0.32, py + (m - py) * 0.32) for px, py in pts])
            c.paint(inner, fill)
        return c.array()
    for d in ("up", "down", "left", "right"):
        for state in STATES:
            out[f"arrow-{d}-{state}"] = tri(d, DISABLED_LINE if state == "disabled" else OUTLINE)
    for state in STATES:
        out[f"arrow-plus-{state}"] = tri("right", DISABLED_LINE if state == "disabled" else OUTLINE)
        out[f"arrow-minus-{state}"] = tri("down", DISABLED_LINE if state == "disabled" else OUTLINE)
    for state in ("normal", "focused", "pressed", "disabled"):
        ink = DISABLED_LINE if state == "disabled" else OUTLINE
        fill = (110, 110, 110) if state == "pressed" else (230, 230, 230) if state == "disabled" else (156, 156, 156)
        out[f"disclosure-plus-{state}"] = tri("right", ink, 10, fill)
        out[f"disclosure-minus-{state}"] = tri("down", ink, 10, fill)
        out[f"menuitem-right-{state}"] = tri("right", (255, 255, 255) if state == "focused" else ink)
        out[f"menuitem-left-{state}"] = tri("left", (255, 255, 255) if state == "focused" else ink)

    # the scrollbar's arrows: Kvantum draws them as an indicator only, so each is a whole bevelled box with its solid
    # arrow, 16 pixels like the scrollbar; a horizontal bar uses them transposed
    def arrow_in_box(direction, state):
        if state in ("pressed", "toggled"):
            c = bevel_box(16, 16, 0, 0, OUTLINE, (100, 100, 100), (170, 170, 170), (136, 136, 136))
        elif state == "disabled":
            c = bevel_box(16, 16, 0, 0, (150, 150, 150), (242, 242, 242), (210, 210, 210), FACE)
        else:
            c = bevel_box(16, 16, 0, 0, OUTLINE, LIGHT, SHADOW, FACE)
        pts = {"up": [(3.5, 10.5), (12.5, 10.5), (8, 5)], "down": [(3.5, 5.5), (12.5, 5.5), (8, 11)]}[direction]
        c.paint(c.polygon(pts), (150, 150, 150) if state == "disabled" else OUTLINE)
        return c.array()
    for d in ("up", "down"):
        for state in STATES:
            out[f"sarrowbox-{d}-{state}"] = arrow_in_box(d, state)
    # the pop-up menu's arrow (Kvantum asks for INDICATOR-STATE here)
    for state in STATES:
        out[f"popuparrow-{state}"] = tri("down", DISABLED_LINE if state == "disabled" else OUTLINE)

    # menus, the menu bar, menu items and tooltips
    def menu_frame(state):
        c = Canvas(4, 4)
        c.paint(c.rect(0), OUTLINE)
        c.paint(c.rect(1), FACE)
        return c.array()
    framed("menu", 1, menu_frame)
    for state in STATES:
        c = Canvas(2, 2)
        if state in ("focused", "pressed", "toggled"):
            c.paint(c.rect(0), A["accent"])
        out[f"menuitem-{state}"] = c.array()
        c = Canvas(2, 2)
        if state in ("pressed", "toggled"):
            c.paint(c.rect(0), A["accent"])
        out[f"menubaritem-{state}"] = c.array()
    sepa = Canvas(8, 10)
    sepa.paint(sepa.rect(0, box=(0, 4, 8, 5)), SHADOW)
    sepa.paint(sepa.rect(0, box=(0, 5, 8, 6)), LIGHT)
    out["menuitem-separator"] = out["menuitem-separator0"] = sepa.array()
    for state in ("normal", "focused"):
        t = Canvas(8, 6)
        for xx in range(0, 8, 4):
            t.paint(t.rect(0, box=(xx, 2, xx + 2, 3)), A["accent"] if state == "focused" else SHADOW)
        out[f"menuitem-tearoff-{state}"] = t.array()

    def menubar(state):
        c = Canvas(4, 4)
        c.paint(c.rect(0), FACE)
        c.paint(c.rect(0, box=(0, 3, 4, 4)), OUTLINE)
        return c.array()
    framed("menubar", (1, 1, 1, 1), menubar)

    def tooltip(state):
        c = Canvas(4, 4)
        c.paint(c.rect(0), OUTLINE)
        c.paint(c.rect(1), TOOLTIP)
        return c.array()
    framed("tooltip", 1, tooltip)

    # check boxes and radio buttons, 13 pixels
    def checkbox(state, mark):
        pressed = state == "pressed"
        dis = state == "disabled"
        c = bevel_box(13, 13, 0, 1.5, DISABLED_LINE if dis else OUTLINE, (120, 120, 120) if pressed else LIGHT,
                      (230, 230, 230) if pressed else SHADOW, (176, 176, 176) if pressed else FACE if dis else (240, 240, 240))
        ink = (150, 150, 150) if dis else OUTLINE
        if mark == "checked":
            c.paint(c.line([(3.2, 6.8), (5.6, 9.4), (10.0, 3.6)], 2.0), ink)
        elif mark == "tristate":
            c.paint(c.rect(0, box=(3, 6, 10, 8)), ink)
        return c.array()

    def radio(state, mark):
        pressed = state == "pressed"
        dis = state == "disabled"
        c = Canvas(13, 13)
        c.paint(c.disc(6.5, 6.5, 6.4), DISABLED_LINE if dis else OUTLINE)
        inner = c.disc(6.5, 6.5, 5.4)
        lit = (c.x + c.y) < 13
        c.paint(inner & lit, (120, 120, 120) if pressed else LIGHT)
        c.paint(inner & ~lit, (230, 230, 230) if pressed else SHADOW)
        c.paint(c.disc(6.5, 6.5, 4.4), (176, 176, 176) if pressed else FACE if dis else (240, 240, 240))
        if mark == "checked":
            c.paint(c.disc(6.5, 6.5, 2.6), (150, 150, 150) if dis else OUTLINE)
        return c.array()
    for state in ("normal", "focused", "pressed", "disabled"):
        out[f"checkbox-{state}"] = checkbox(state, None)
        out[f"checkbox-checked-{state}"] = checkbox(state, "checked")
        out[f"checkbox-tristate-{state}"] = checkbox(state, "tristate")
        out[f"radio-{state}"] = radio(state, None)
        out[f"radio-checked-{state}"] = radio(state, "checked")

    # dials (QDial): a bevelled knob with an accent mark
    d = Canvas(32, 32)
    d.paint(d.disc(16, 16, 15.5), OUTLINE)
    d.paint(d.disc(16, 16, 14.5) & ((d.x + d.y) < 32), LIGHT)
    d.paint(d.disc(16, 16, 14.5) & ((d.x + d.y) >= 32), SHADOW)
    d.paint(d.disc(16, 16, 13.5), FACE)
    out["dial"] = d.array()
    h = Canvas(8, 8)
    h.paint(h.disc(4, 4, 3.5), A["accent"])
    out["dial-handle"] = h.array()
    out["dial-notches"] = out["dial-notches0"] = transparent(4, 4)
    out["base"] = transparent(2, 2)

    # ids Kvantum's own default theme has for these families that this theme draws as nothing (frameless item views
    # and menu bar items, no menu or tooltip shadows, alternate ids): present and empty, so no default artwork appears
    sides = ("top", "bottom", "left", "right")
    parts = sides + ("topleft", "topright", "bottomleft", "bottomright")
    for p in parts:
        for st in ("focused", "pressed", "toggled"):
            out.setdefault(f"itemview-{st}-{p}", transparent())
        out.setdefault(f"itemview-pressed-{p}1", transparent())
        for st in ("pressed", "toggled"):
            out.setdefault(f"menubaritem-{st}-{p}", transparent())
        out.setdefault(f"menu-normal-{p}0", transparent())
        for kind in ("menu", "tooltip"):
            out.setdefault(f"{kind}-shadow-{p}", transparent())
        out[f"focus-normal-{p}"] = out[f"focus-disabled-{p}"] = out[f"focus-{p}"]
    for side in sides:
        for kind in ("menu", "tooltip"):
            out.setdefault(f"{kind}-shadow-hint-{side}", transparent())
    out["menuitem-pressed1"] = out["menuitem-pressed"]
    out["button-default-indicator0"] = transparent(8, 8)
    out["dock-disabled"] = out["dock-normal"]
    out["titlebar-disabled"] = out["titlebar-normal"]
    out["splitter-disabled"] = out["splitter-normal"]
    return out


# ---------------------------------------------------------------- SVG writing
def fill(px):
    colour = "#%02x%02x%02x" % tuple(int(v) for v in px[:3])
    return f'fill="{colour}"' + ("" if px[3] >= 1 else f' fill-opacity="{px[3]:.3f}"')


def rects(arr, x0, y0):
    """The pixels as the fewest rectangles: runs merged across a row, then identical runs merged down the rows.
    Kvantum stretches a part to any size, and stacked one-pixel rectangles then meet at fractional, antialiased edges
    that let the background through (light seams across a scroll track, found in the gallery); so an opaque element
    also gets one rectangle of its most frequent colour underneath, and the others are drawn over it."""
    h, w = arr.shape[:2]
    key = [[tuple(arr[yy, xx]) for xx in range(w)] for yy in range(h)]
    out = []
    base = None
    if arr[..., 3].min() >= 1:
        counts = {}
        for row in key:
            for px in row:
                counts[px] = counts.get(px, 0) + 1
        base = max(counts, key=counts.get)
        out.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" {fill(base)}/>')
    runs = []
    for yy in range(h):
        xx = 0
        row = []
        while xx < w:
            px = key[yy][xx]
            end = xx + 1
            while end < w and key[yy][end] == px:
                end += 1
            if px[3] > 0 and px != base:
                row.append((xx, end - xx, px))
            xx = end
        runs.append(row)
    done = set()
    for yy in range(h):
        for (xx, rw, px) in runs[yy]:
            if (yy, xx) in done:
                continue
            hh = 1
            while yy + hh < h and (xx, rw, px) in runs[yy + hh]:
                done.add((yy + hh, xx))
                hh += 1
            out.append(f'<rect x="{x0 + xx}" y="{y0 + yy}" width="{rw}" height="{hh}" {fill(px)}/>')
    return out


def svg(elements_by_id):
    """Each element as a group of pixel rectangles; an invisible rectangle first gives every group its full bounds,
    so Kvantum scales an element by its pixel size even where its edges are transparent."""
    parts, x, y, row = [], 0, 0, 0
    width = 1024
    for eid in sorted(elements_by_id):
        arr = elements_by_id[eid]
        h, w = arr.shape[:2]
        if x + w > width:
            x, y, row = 0, y + row + 4, 0
        body = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#000000" fill-opacity="0"/>']
        body += rects(arr, x, y)
        parts.append(f'<g id="{eid}">' + "".join(body) + "</g>")
        x += w + 4
        row = max(row, h)
    height = y + row + 4
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" shape-rendering="crispEdges">\n'
            + "\n".join(parts) + "\n</svg>\n")


COMMENT = {
    "en": "Kubabbar Glass 9: classic bevelled controls in the {accent} accent, original drawings. Scroll arrows {arrows}.",
    "pl": "Kubabbar Glass 9: klasyczne, wypukłe kontrolki w akcencie {accent}, oryginalne rysunki. Strzałki przewijania {arrows}.",
    "pt_BR": "Kubabbar Glass 9: controles clássicos em relevo no destaque {accent}, desenhos originais. Setas de rolagem {arrows}.",
    "fr": "Kubabbar Glass 9 : commandes classiques en relief, accent {accent}, dessins originaux. Flèches de défilement {arrows}.",
    "de": "Kubabbar Glass 9: klassische, plastische Bedienelemente in der Akzentfarbe {accent}, eigene Zeichnungen. Bildlaufpfeile {arrows}.",
    "es": "Kubabbar Glass 9: controles clásicos en relieve con el acento {accent}, dibujos originales. Flechas de desplazamiento {arrows}.",
    "ja": "Kubabbar Glass 9: アクセント {accent} の立体的なクラシックコントロール、オリジナルの描画。スクロール矢印は{arrows}。",
    "ko": "Kubabbar Glass 9: {accent} 강조색의 입체적인 클래식 컨트롤, 독자적인 그림. 스크롤 화살표는 {arrows}.",
    "zh_CN": "Kubabbar Glass 9：{accent}强调色的经典立体控件，原创绘制。滚动箭头{arrows}。",
    "zh_TW": "Kubabbar Glass 9：{accent}強調色的經典立體控制項，原創繪製。捲動箭頭{arrows}。",
}
ARROWS = {
    True: {"en": "together at the end", "pl": "razem na końcu", "pt_BR": "juntas no fim", "fr": "groupées à la fin",
           "de": "zusammen am Ende", "es": "juntas al final", "ja": "末端にまとめて配置", "ko": "끝에 함께 있음",
           "zh_CN": "集中在末端", "zh_TW": "集中在末端"},
    False: {"en": "at both ends", "pl": "na obu końcach", "pt_BR": "nas duas pontas", "fr": "aux deux extrémités",
            "de": "an beiden Enden", "es": "en ambos extremos", "ja": "両端に配置", "ko": "양쪽 끝에 있음",
            "zh_CN": "位于两端", "zh_TW": "位於兩端"},
}


def kvconfig(accent, together):
    names = ACCENT_NAMES[accent]
    lines = ["[%General]", "author=Daniel Ramos and EchoSystems AI studios"]
    lines.append("comment=" + COMMENT["en"].format(accent=names["en"], arrows=ARROWS[together]["en"]))
    lines += [f"comment[{lang}]=" + COMMENT[lang].format(accent=names[lang], arrows=ARROWS[together][lang])
              for lang in LANGUAGES if lang != "en"]
    lines += ["x11drag=menubar_and_primary_toolbar", "alt_mnemonic=true", "left_tabs=false", "joined_inactive_tabs=false",
              "attach_active_tab=false", "group_toolbar_buttons=false", "composite=false", "menu_shadow_depth=0",
              "tooltip_shadow_depth=0", "splitter_width=7", "scroll_width=16", "scroll_min_extent=28", "scroll_arrows=true",
              f"scroll_arrows_together={'true' if together else 'false'}", "center_scrollbar_indicator=true",
              "transient_scrollbar=false", "scrollbar_in_view=false", "slider_width=6", "slider_handle_width=16",
              "slider_handle_length=16", "check_size=13", "vertical_spin_indicators=true", "spread_progressbar=true",
              "progressbar_thickness=12", "tree_branch_line=false", "menubar_mouse_tracking=true",
              "merge_menubar_with_toolbar=false", "button_contents_shift=false", "fill_rubberband=false",
              "respect_DE=true", "translucent_windows=false", "blurring=false", "popup_blurring=false",
              "animate_states=false", "no_inactiveness=false", "",
              "[Hacks]", "respect_darkness=false", "",
              "[PanelButtonCommand]", "frame=true", "frame.element=button", "frame.top=6", "frame.bottom=6", "frame.left=6",
              "frame.right=6", "interior=true", "interior.element=button", "indicator.size=9", "indicator.element=arrow",
              "text.press.color=#ffffff", "text.toggle.color=#ffffff", "text.shadow=false", "text.margin.top=1",
              "text.margin.bottom=1", "text.margin.left=6", "text.margin.right=6", "text.iconspacing=4", "",
              "[PanelButtonTool]", "inherits=PanelButtonCommand", "frame.element=tbutton", "interior.element=tbutton",
              "frame.top=3", "frame.bottom=3", "frame.left=3", "frame.right=3", "text.press.color=none",
              "text.toggle.color=none", "text.margin.left=3", "text.margin.right=3", "",
              "[ToolboxTab]", "inherits=PanelButtonTool", "",
              "[Dock]", "inherits=PanelButtonCommand", "frame=false", "interior=false", "",
              "[DockTitle]", "inherits=PanelButtonCommand", "frame=false", "interior=true", "interior.element=dock",
              "text.press.color=none", "text.toggle.color=none", "text.margin.top=2", "text.margin.bottom=2", "",
              "[IndicatorSpinBox]", "inherits=PanelButtonCommand", "frame.element=spin", "interior.element=spin",
              "frame.top=2", "frame.bottom=2", "frame.left=2", "frame.right=2", "indicator.element=arrow",
              "indicator.size=8", "text.press.color=none", "text.toggle.color=none", "",
              "[RadioButton]", "inherits=PanelButtonCommand", "frame=false", "interior.element=radio",
              "text.press.color=none", "text.toggle.color=none", "text.margin.top=2", "text.margin.bottom=2",
              "text.margin.left=3", "text.margin.right=3", "",
              "[CheckBox]", "inherits=RadioButton", "interior.element=checkbox", "",
              "[Focus]", "frame=true", "interior=false", "frame.element=focus", "frame.top=1", "frame.bottom=1",
              "frame.left=1", "frame.right=1", "",
              "[GenericFrame]", "frame=true", "interior=false", "frame.element=common", "interior.element=common",
              "frame.top=2", "frame.bottom=2", "frame.left=2", "frame.right=2", "",
              "[LineEdit]", "inherits=PanelButtonCommand", "frame.element=lineedit", "interior.element=lineedit",
              "frame.top=3", "frame.bottom=3", "frame.left=3", "frame.right=3", "text.press.color=none",
              "text.toggle.color=none", "",
              "[ComboBox]", "inherits=PanelButtonCommand", "frame.element=combo", "interior.element=combo",
              "frame.top=3", "frame.bottom=3", "frame.left=3", "frame.right=3", "indicator.element=popuparrow",
              "indicator.size=9", "text.press.color=none", "text.toggle.color=none", "",
              "[DropDownButton]", "inherits=ComboBox", "indicator.element=popuparrow", "",
              "[IndicatorArrow]", "indicator.element=arrow", "indicator.size=8", "",
              "[Tab]", "inherits=PanelButtonCommand", "frame.element=tab", "interior.element=tab", "indicator.element=tab",
              "frame.top=4", "frame.bottom=1", "frame.left=3", "frame.right=3", "text.press.color=none",
              "text.toggle.color=none", "text.margin.left=8", "text.margin.right=8", "",
              "[TabFrame]", "inherits=PanelButtonCommand", "frame.element=tabframe", "interior.element=tabframe",
              "frame.top=2", "frame.bottom=2", "frame.left=2", "frame.right=2", "",
              "[TabBarFrame]", "frame=false", "interior=false", "",
              "[TreeExpander]", "inherits=PanelButtonCommand", "frame=false", "interior=false",
              "indicator.element=disclosure", "indicator.size=10", "",
              "[HeaderSection]", "inherits=PanelButtonCommand", "frame.element=header", "interior.element=header",
              "frame.top=1", "frame.bottom=1", "frame.left=1", "frame.right=1", "text.press.color=none",
              "text.toggle.color=none", "",
              "[SizeGrip]", "indicator.element=sizegrip", "",
              "[Toolbar]", "inherits=PanelButtonCommand", "frame.element=toolbar", "interior.element=toolbar",
              "indicator.element=toolbar", "indicator.size=5", "frame.top=1", "frame.bottom=1", "frame.left=1",
              "frame.right=1", "text.press.color=none", "text.toggle.color=none", "",
              "[Slider]", "inherits=PanelButtonCommand", "frame.element=slider", "interior.element=slider",
              "frame.top=2", "frame.bottom=2", "frame.left=2", "frame.right=2", "",
              "[SliderCursor]", "inherits=PanelButtonCommand", "frame=false", "interior.element=slidercursor", "",
              "[Progressbar]", "inherits=PanelButtonCommand", "frame.element=progress", "interior.element=progress",
              "frame.top=2", "frame.bottom=2", "frame.left=2", "frame.right=2", "text.press.color=none",
              "text.toggle.color=none", "text.bold=false", "",
              "[ProgressbarContents]", "inherits=PanelButtonCommand", "frame=false",
              "interior.element=progress-pattern", "",
              "[ItemView]", "inherits=PanelButtonCommand", "frame=false", "interior=true", "interior.element=itemview",
              "text.margin=0", "text.press.color=none", "text.toggle.color=none", "",
              "[Splitter]", "frame=false", "interior=true", "interior.element=splitter",
              "indicator.element=splitter-grip", "indicator.size=16", "",
              "[Scrollbar]", "inherits=PanelButtonCommand", "frame=false", "interior=false",
              "indicator.element=sarrowbox", "indicator.size=16", "",
              "[ScrollbarSlider]", "inherits=PanelButtonCommand", "frame.element=scrollbarslider",
              "interior.element=scrollbarslider", "frame.top=2", "frame.bottom=2", "frame.left=2", "frame.right=2",
              "indicator.element=grip", "indicator.size=8", "",
              "[ScrollbarGroove]", "inherits=PanelButtonCommand", "frame.element=sgroove", "interior.element=sgroove",
              "frame.top=1", "frame.bottom=1", "frame.left=1", "frame.right=1", "",
              "[MenuItem]", "inherits=PanelButtonCommand", "frame=false", "interior.element=menuitem",
              "indicator.element=menuitem", "min_height=20", "text.focus.color=#ffffff", "text.press.color=#ffffff",
              "text.toggle.color=#ffffff", "text.margin.top=1", "text.margin.bottom=1", "text.margin.left=6",
              "text.margin.right=6", "",
              "[MenuBarItem]", "inherits=PanelButtonCommand", "frame=false", "interior.element=menubaritem",
              "text.focus.color=none", "text.press.color=#ffffff", "text.toggle.color=#ffffff", "text.margin.top=2",
              "text.margin.bottom=2", "text.margin.left=6", "text.margin.right=6", "",
              "[MenuBar]", "inherits=PanelButtonCommand", "frame.element=menubar", "interior.element=menubar",
              "frame.top=0", "frame.bottom=1", "frame.left=0", "frame.right=0", "",
              "[TitleBar]", "inherits=PanelButtonCommand", "frame=false", "interior.element=titlebar",
              "indicator.size=12", "indicator.element=mdi", "text.press.color=none", "text.toggle.color=none", "",
              "[Menu]", "inherits=PanelButtonCommand", "frame.element=menu", "interior.element=menu", "frame.top=1",
              "frame.bottom=1", "frame.left=1", "frame.right=1", "",
              "[GroupBox]", "inherits=GenericFrame", "frame=true", "frame.element=group", "interior=false",
              "text.margin=0", "",
              "[ToolTip]", "inherits=GenericFrame", "frame.element=tooltip", "interior=true", "interior.element=tooltip",
              "frame.top=1", "frame.bottom=1", "frame.left=1", "frame.right=1", "text.margin=2", "",
              "[Window]", "interior=false"]
    return "\n".join(lines) + "\n"


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    for accent in ACCENTS:
        together = kvantum_name(accent, True)
        apart = kvantum_name(accent, False)
        (ROOT / together).mkdir(exist_ok=True)
        (ROOT / together / f"{together}.svg").write_text(svg(elements(accent)))
        (ROOT / together / f"{together}.kvconfig").write_text(kvconfig(accent, True))
        (ROOT / apart).mkdir(exist_ok=True)
        (ROOT / apart / f"{apart}.kvconfig").write_text(kvconfig(accent, False))
        link = ROOT / apart / f"{apart}.svg"
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(f"../{together}/{together}.svg")
        print("wrote", together, apart)


if __name__ == "__main__":
    main()
