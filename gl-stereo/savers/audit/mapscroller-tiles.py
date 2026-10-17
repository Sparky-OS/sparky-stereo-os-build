#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Fill a home's Mapscroller cache with synthetic tiles at the coordinates the audit asks for.

usage: mapscroller-tiles.py <home>
       mapscroller-tiles.py --missed <log>...     (the tiles the helper tried to download)
       mapscroller-tiles.py --requested <log>...  (every tile the helper served or tried)
Finding the list again: with the network off, give a home extra tiles around the scene
(MAPSCROLLER_TILES_EXTRA="z:y0-y1:x0-x1", cache coordinates), run the audit's Mapscroller
producers, and take --requested from their logs.
Mapscroller's helper serves a tile from its cache when the file exists, so with these files
and the network off the saver's input is fixed. Every tile is drawn here from its coordinates:
no map imagery is stored, fetched or shipped (README.md, "Mapscroller's tiles").
"""
import hashlib
import json
import os
import re
from pathlib import Path
import sys
from PIL import Image, ImageDraw

fixture = json.loads(Path(__file__).with_name('mapscroller-tiles.json').read_text())
if sys.argv[1] == '--missed':
    # "downloading https://a.tile.openstreetmap.org/15/X/Y.png": the cache keeps it as 15/Y/X
    missed = set()
    for log in sys.argv[2:]:
        for z, x, y in re.findall(r'downloading https?://[^/ ]*/(\d+)/(\d+)/(\d+)\.png', Path(log).read_text(errors='replace')):
            missed.add(f'{z}/{y}/{x}')
    print('\n'.join(sorted(missed - set(fixture['tiles']))))
    sys.exit(0)
if sys.argv[1] == '--requested':
    # "cached: X Y Z" and the downloads, both as cache paths Z/Y/X
    requested = set()
    for log in sys.argv[2:]:
        text = Path(log).read_text(errors='replace')
        requested |= {f'{z}/{y}/{x}' for x, y, z in re.findall(r'cached: (\d+) (\d+) (\d+)', text)}
        requested |= {f'{z}/{y}/{x}' for z, x, y in re.findall(r'downloading https?://[^/ ]*/(\d+)/(\d+)/(\d+)\.png', text)}
    print('\n'.join(sorted(requested)))
    sys.exit(0)
home = Path(sys.argv[1])
root = home/'.cache'/'xscreensaver'/'mapscroller'/fixture['site']
tiles = list(fixture['tiles'])
if os.environ.get('MAPSCROLLER_TILES_EXTRA'):
    z, ys, xs = os.environ['MAPSCROLLER_TILES_EXTRA'].split(':')
    (y0, y1), (x0, x1) = (map(int, r.split('-')) for r in (ys, xs))
    tiles += [f'{z}/{y}/{x}' for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
for tile in tiles:
    seed = hashlib.sha256(tile.encode()).digest()
    picture = Image.new('RGB', (256, 256), (96 + seed[0] % 128, 96 + seed[1] % 128, 96 + seed[2] % 128))
    draw = ImageDraw.Draw(picture)
    # streets: a grid offset per tile, and one diagonal; blocks: a few filled squares
    for i in range(0, 256, 32):
        draw.line((i + seed[3] % 32, 0, i + seed[3] % 32, 255), fill=(240, 240, 230), width=3)
        draw.line((0, i + seed[4] % 32, 255, i + seed[4] % 32), fill=(240, 240, 230), width=3)
    draw.line((0, seed[5], 255, seed[6]), fill=(250, 200, 80), width=5)
    for k in range(4):
        x, y = seed[7 + 2 * k] % 224, seed[8 + 2 * k] % 224
        draw.rectangle((x, y, x + 24, y + 24), fill=(seed[16 + k] % 160, 120 + seed[20 + k] % 100, 90))
    path = root/(tile + '.png')
    path.parent.mkdir(parents=True, exist_ok=True)
    picture.save(path, optimize=False)
print('synthetic tiles:', len(set(tiles)), 'in', root)
