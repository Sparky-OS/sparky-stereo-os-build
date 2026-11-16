#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
"""The +24 source's Vulkan stereo layer takes its own messages (debian/lang-layer: the pair's LOCAL1 and LOCAL2,
and LOCAL3 and LOCAL4 for a program refused two views) in its journal catalogs."""
from pathlib import Path
import sys
source, out = map(Path, sys.argv[1:])
old = ('\tsparky-stereo-problems catalog mesa-vulkan-layer-stereo debian/lang-pair '
       'debian/mesa-vulkan-layer-stereo/usr/lib/systemd/catalog --subject LOCAL1\n')
new = ('\tsparky-stereo-problems catalog mesa-vulkan-layer-stereo debian/lang-layer '
       'debian/mesa-vulkan-layer-stereo/usr/lib/systemd/catalog --subject LOCAL1 --subject LOCAL3=LOCAL4\n')
s = (source / 'rules').read_text()
if s.count(old) != 1:
    raise SystemExit(f'expected one packaging anchor: {old!r}')
(out / 'rules').write_text(s.replace(old, new))
