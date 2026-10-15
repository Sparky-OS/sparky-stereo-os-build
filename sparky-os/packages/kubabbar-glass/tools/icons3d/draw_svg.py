#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""The scalable 2D drawing of the Kubabbar Glass trash icons: a silver bin with smooth metal gradients (no raster steps), empty and full."""
import sys
from pathlib import Path

HEAD = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n<!-- SPDX-License-Identifier: GPL-3.0-only. Original artwork of Kubabbar Glass. -->\n'
DEFS = '''<defs>
<linearGradient id="metal" x1="0" y1="0" x2="1" y2="0">
<stop offset="0" stop-color="#5f676f"/><stop offset=".10" stop-color="#9ea6ad"/><stop offset=".22" stop-color="#e9edf0"/>
<stop offset=".34" stop-color="#bcc3c9"/><stop offset=".50" stop-color="#7b838b"/><stop offset=".64" stop-color="#b5bcc2"/>
<stop offset=".80" stop-color="#e2e6e9"/><stop offset=".92" stop-color="#8d959c"/><stop offset="1" stop-color="#555d65"/>
</linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="1" y2="0">
<stop offset="0" stop-color="#7d858c"/><stop offset=".25" stop-color="#f4f6f8"/><stop offset=".5" stop-color="#aab2b8"/>
<stop offset=".75" stop-color="#f0f2f4"/><stop offset="1" stop-color="#737b83"/>
</linearGradient>
<radialGradient id="inside" cx=".5" cy=".35" r=".7">
<stop offset="0" stop-color="#8a9299"/><stop offset=".6" stop-color="#4b5258"/><stop offset="1" stop-color="#2e3338"/>
</radialGradient>
<radialGradient id="shadow" cx=".5" cy=".5" r=".5">
<stop offset="0" stop-color="#000" stop-opacity=".42"/><stop offset=".6" stop-color="#000" stop-opacity=".16"/><stop offset="1" stop-color="#000" stop-opacity="0"/>
</radialGradient>
<radialGradient id="sheet" cx=".4" cy=".3" r=".8">
<stop offset="0" stop-color="#ffffff"/><stop offset=".7" stop-color="#e6e9eb"/><stop offset="1" stop-color="#c3c8cc"/>
</radialGradient>
</defs>
'''
BODY = '''<ellipse cx="128" cy="222" rx="104" ry="22" fill="url(#shadow)"/>
<path d="M48 70 L66 212 A62 17 0 0 0 190 212 L208 70 Z" fill="url(#metal)"/>
<g fill="none" stroke-linecap="round">
<path d="M53 108 A75 20 0 0 0 203 108" stroke="#4f565d" stroke-width="3" opacity=".55"/><path d="M53 105.5 A75 20 0 0 0 203 105.5" stroke="#f7f9fa" stroke-width="1.6" opacity=".8"/>
<path d="M57 140 A71 19 0 0 0 199 140" stroke="#4f565d" stroke-width="3" opacity=".55"/><path d="M57 137.5 A71 19 0 0 0 199 137.5" stroke="#f7f9fa" stroke-width="1.6" opacity=".8"/>
<path d="M61 172 A67 18 0 0 0 195 172" stroke="#4f565d" stroke-width="3" opacity=".55"/><path d="M61 169.5 A67 18 0 0 0 195 169.5" stroke="#f7f9fa" stroke-width="1.6" opacity=".8"/>
<path d="M66 208 A62 17 0 0 0 190 208" stroke="#d8dde1" stroke-width="3"/>
</g>
<ellipse cx="128" cy="70" rx="80" ry="22" fill="url(#inside)"/>
'''
EMPTY_TOP = '<ellipse cx="128" cy="70" rx="80" ry="22" fill="none" stroke="url(#rim)" stroke-width="7"/>\n<ellipse cx="128" cy="68.5" rx="78" ry="20" fill="none" stroke="#ffffff" stroke-opacity=".5" stroke-width="1.5"/>\n'
PAPER = '''<g>
<ellipse cx="96" cy="60" rx="30" ry="24" fill="url(#sheet)"/><ellipse cx="156" cy="58" rx="32" ry="25" fill="url(#sheet)"/>
<ellipse cx="124" cy="44" rx="34" ry="28" fill="url(#sheet)"/><ellipse cx="82" cy="46" rx="22" ry="19" fill="url(#sheet)"/>
<ellipse cx="170" cy="44" rx="23" ry="19" fill="url(#sheet)"/>
<g fill="none" stroke="#9aa0a5" stroke-width="1.2" stroke-linecap="round" opacity=".7">
<path d="M108 36 q8 8 4 18 M135 32 q-6 10 3 20 M90 52 q10 -2 14 8 M150 52 q9 4 12 14 M162 38 q-4 6 0 12 M76 42 q6 2 8 9"/>
</g></g>
'''
RIM_FRONT = '<path d="M48 70 A80 22 0 0 0 208 70" fill="none" stroke="url(#rim)" stroke-width="7"/>\n<path d="M52 72 A76 20 0 0 0 204 72" fill="none" stroke="#ffffff" stroke-opacity=".45" stroke-width="1.4"/>\n'


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "user-trash.svg").write_text(HEAD + DEFS + BODY + EMPTY_TOP + "</svg>\n")
    (out / "user-trash-full.svg").write_text(HEAD + DEFS + BODY + PAPER + RIM_FRONT + "</svg>\n")
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
