#!/usr/bin/env python3
"""Reject stripes beneath the caption and the former white wallpaper artefact."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
records = []
for eye in ('LEFT', 'RIGHT'):
    image = Image.open(root / f'evidence/windows-classic-black-stereo/{eye}.png').convert('RGB')
    # The caption is centred between the two button groups, so find its text first (the first dark column after the left buttons),
    # then read the backing just left of it and the stripes further left, between the buttons and the backing.
    text_left = next(x for x in range(770, 1240) if any(sum(image.getpixel((x, y))) < 330 for y in range(437, 453)))
    backing = {image.getpixel((text_left - 3, y)) for y in range(437, 453)}
    stripes = {image.getpixel((text_left - 20, y)) for y in range(437, 453)}
    assert backing == {(216, 217, 213)}, (eye, backing)
    assert len(stripes) >= 3, (eye, stripes)
    records.append({'eye': eye, 'caption_backing_rgb': sorted(backing), 'stripe_colours': len(stripes)})
image = Image.open(root / 'evidence/2d/desktop.png').convert('RGB')
wallpaper = set(image.crop((1100, 500, 1500, 850)).get_flattened_data())
assert len(wallpaper) > 1 and all(100 <= channel <= 170 for rgb in wallpaper for channel in rgb), wallpaper
(root / 'evidence/caption-wallpaper.json').write_text(json.dumps({'caption': records, 'wallpaper_colours': len(wallpaper)}, indent=2) + '\n')
print('PASS: plain caption backing within striped active title in both eyes; quiet wallpaper without white pattern artefacts')
