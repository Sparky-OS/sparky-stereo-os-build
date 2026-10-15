#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Draws the original artwork of the System 8 layout variant: the launcher logo and the splash logo.
# The logo is an eight-pointed star (the star of Ishtar, an ancient Mesopotamian sign, public domain) in a silver glass disc.
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def star(cx, cy, outer, inner, points=8, turn=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = turn + i * math.pi / points
        pts.append("%.2f,%.2f" % (cx + r * math.cos(a), cy + r * math.sin(a)))
    return " ".join(pts)


def logo(size=256, flat=False):
    c = size / 2
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 256 256">
  <!-- SPDX-License-Identifier: GPL-3.0-only; original artwork, Daniel Ramos and EchoSystems AI studios, 2026 -->
  <defs>
    <radialGradient id="disc" cx="0.38" cy="0.3" r="0.9">
      <stop offset="0" stop-color="#fbfcf8"/>
      <stop offset="0.45" stop-color="#d3d6cf"/>
      <stop offset="0.8" stop-color="#9ea59b"/>
      <stop offset="1" stop-color="#7b8479"/>
    </radialGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="1" stop-color="#565f54"/>
    </linearGradient>
    <linearGradient id="starfill" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#4b6a3a"/>
      <stop offset="1" stop-color="#26361f"/>
    </linearGradient>
    <radialGradient id="shine" cx="0.5" cy="0" r="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.85"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <circle cx="128" cy="128" r="120" fill="url(#disc)" stroke="url(#rim)" stroke-width="6"/>
  <polygon points="{star(128, 132, 92, 40)}" fill="url(#starfill)" stroke="#1b2519" stroke-width="3" stroke-linejoin="round"/>
  <circle cx="128" cy="132" r="13" fill="#e8ebe1" stroke="#1b2519" stroke-width="3"/>
  <ellipse cx="128" cy="62" rx="86" ry="52" fill="url(#shine)"/>
</svg>
'''


def main():
    out = ROOT / "share/icons/hicolor/scalable/apps/kubabbar-glass-launcher.svg"
    out.write_text(logo())
    splash = ROOT / "share/plasma/look-and-feel/kubabbar-glass-menubar/contents/splash/images/logo.svg"
    splash.parent.mkdir(parents=True, exist_ok=True)
    splash.write_text(logo())
    print(out, splash)


if __name__ == "__main__":
    main()
