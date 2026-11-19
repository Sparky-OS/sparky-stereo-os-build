#!/usr/bin/python3
# Copyright 2026 Daniel Campos Ramos, GPL-3.0-or-later.
"""Install upstream's artwork in indexed hicolor application directories."""
from pathlib import Path
import shutil
import sys

from PIL import Image

source, destination = map(Path, sys.argv[1:])
with Image.open(source) as original:
    if original.size != (1024, 1024):
        raise SystemExit('The pinned upstream icon must be 1024 by 1024')
    image = original.convert('RGBA')
    for size in (16, 22, 24, 32, 48, 64, 96, 128, 256, 512):
        path = destination / f'{size}x{size}/apps/spirula-studio.png'
        path.parent.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(path)
path = destination / '1024x1024/apps/spirula-studio.png'
path.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source, path)
