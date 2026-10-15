#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Derive the Kubabbar Glass Kvantum theme from KvGnome (Tsu Jan, GPL-3.0+): the same bevelled shapes, recoloured with the look's palette."""
import colorsys
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = pathlib.Path("/usr/share/Kvantum/KvGnome")
OUT = ROOT / "share/Kvantum/KubabbarGlass"
GREEN_HUE = 104 / 360
GREY_HUE = 75 / 360


def recolour(match):
    text = match.group(0)
    r, g, b = (int(text[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if 180 / 360 <= h <= 300 / 360 and s > 0.3:
        h, s, l = GREEN_HUE, s * 0.45, l * 0.7
    elif s < 0.15 and 0.35 < l < 0.99:
        h, s = GREY_HUE, 0.05
    else:
        return text
    return "#%02x%02x%02x" % tuple(round(c * 255) for c in colorsys.hls_to_rgb(h, l, s))


PALETTE = {
    "window.color": "#d8d9d5", "inactive.window.color": "#d8d9d5", "base.color": "#f9faf6", "inactive.base.color": "#f9faf6",
    "alt.base.color": "#eaede3", "inactive.alt.base.color": "#eaede3", "button.color": "#dfe1da",
    "highlight.color": "#42572f", "inactive.highlight.color": "#697d55", "text.color": "#1b2119", "inactive.text.color": "#1b2119c8",
    "window.text.color": "#1b2119", "inactive.window.text.color": "#5d6557", "button.text.color": "#1b2119",
    "disabled.text.color": "#5c6356", "link.color": "#204b80", "link.visited.color": "#5d3f6b",
    "text.normal.color": "#1b2119", "text.focus.color": "#1b2119", "text.press.color": "#1b2119", "text.toggle.color": "#1b2119",
    "text.normal.inactive.color": "#1b21198c", "text.toggle.inactive.color": "#1b21198c", "highlight.text.color": "#fffffa",
}

OUT.mkdir(parents=True, exist_ok=True)
svg = (SOURCE / "KvGnome.svg").read_text()
(OUT / "KubabbarGlass.svg").write_text(re.sub(r"#[0-9a-fA-F]{6}\b", recolour, svg))
lines = []
for line in (SOURCE / "KvGnome.kvconfig").read_text().splitlines():
    key = line.split("=", 1)[0]
    if key in PALETTE:
        line = "%s=%s" % (key, PALETTE[key])
    elif key == "comment":
        line = "comment=Kubabbar Glass in Kvantum: the KvGnome shapes by Tsu Jan, recoloured with the look's palette."
    elif key == "author":
        line = "author=Tsu Jan (KvGnome shapes); recoloured by Daniel Ramos and EchoSystems AI studios"
    lines.append(line)
(OUT / "KubabbarGlass.kvconfig").write_text("\n".join(lines) + "\n")
shutil.copy("/usr/share/common-licenses/GPL-3", OUT / "COPYING")
print("wrote", OUT)
