#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""prog_analyze.py RUN [RED_RUN]: one row of a program that loads vtk9. Prints JSON: the capture's width (3840 = both eyes),
the declarations (set_content lines, declared X11 windows), the program's largest shown window from KWin's list, how much
its left-eye content varies (distinct colours, standard deviation: a drawn window is not one colour), the VTK and F3D
libraries mapped, whether it exited by itself, and with RED_RUN the share of pixels inside that window that differ from the
same program's red run (left eye)."""
import json, sys
from pathlib import Path
from PIL import Image, ImageStat


def window(run):
    best = None
    for line in (Path(run) / 'windows.txt').read_text(errors='replace').splitlines():
        p = line.split('|')
        if len(p) < 5 or p[4] != 'shown':
            continue
        x, y, w, h = (int(float(v)) for v in p[2].split(','))
        if p[3] in ('plasmashell', 'kwin_wayland', '') or w * h < 40000:
            continue
        if best is None or w * h > best[2] * best[3]:
            best = (x, y, w, h, p[1], p[3])
    return best


def left(run):
    im = Image.open(Path(run) / 'shot1.png').convert('RGB')
    return im if im.width <= 1920 else im.crop((0, 0, im.width // 2, im.height))


run = sys.argv[1]; r = {'run': Path(run).name}
im = Image.open(Path(run) / 'shot1.png'); r['capture'] = list(im.size)
wl = (Path(run) / 'wl.txt').read_text(errors='replace') if (Path(run) / 'wl.txt').exists() else ''
r['set_content'] = wl.count('set_content')
try:
    r['declared_x11'] = len(json.loads((Path(run) / 'props.json').read_text()).get('windows', []))
except Exception:
    r['declared_x11'] = None
w = window(run); r['window'] = list(w[:4]) + [w[4][:40], w[5]] if w else None
if w:
    x, y, ww, hh = (max(0, v) for v in w[:4])
    crop = left(run).crop((x, y, min(1920, x + ww), min(1080, y + hh)))
    r['colours'] = len(crop.getcolors(1 << 24) or [])
    r['stddev'] = round(sum(ImageStat.Stat(crop).stddev) / 3, 1)
maps = (Path(run) / 'maps.txt').read_text().split() if (Path(run) / 'maps.txt').exists() else []
r['libs_mapped'] = len(maps); r['guisupportqt'] = [m for m in maps if 'GUISupportQt' in m]
r['exited_itself'] = (Path(run) / 'rc.txt').read_text().strip() if (Path(run) / 'rc.txt').exists() else None
if len(sys.argv) > 2 and w:
    a, b = left(run), left(sys.argv[2])
    box = (x, y, min(1920, x + ww), min(1080, y + hh))
    pa, pb = a.crop(box).tobytes(), b.crop(box).tobytes()
    n = len(pa) // 3
    r['differs_from_red'] = round(sum(1 for i in range(0, len(pa), 3) if pa[i:i + 3] != pb[i:i + 3]) / max(1, n), 4)
print(json.dumps(r))
