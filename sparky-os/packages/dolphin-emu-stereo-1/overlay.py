#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""Sparky Stereo OS, ORDER 39: the changes to Debian's own debian/ of dolphin-emu 2609.b+dfsg-1: the build declares the
pair through libstereo-declare, and the copyright file credits our additions after Debian's paragraphs. Run in the
unpacked source. Every replace states what it expects and stops when Debian's file is not the one this was written for."""
from pathlib import Path

control = Path('debian/control').read_text()
old = ' libsdl3-dev,\n'
assert control.count(old) == 1, 'Debian control changed'
control = control.replace(old, old + ' libstereo-declare-dev (>= 1.7.0),\n', 1)
Path('debian/control').write_text(control)

copyright = Path('debian/copyright').read_text()
assert 'Files: debian/patches/stereo-' not in copyright
Path('debian/copyright').write_text(copyright.rstrip('\n') + '''

Files: debian/patches/stereo-*
Copyright: 2026 Daniel Campos Ramos
License: GPL-2+
Comment: Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Pawel "pavroo" Pijanowski).
 Dolphin is by the Dolphin Emulator Project and its contributors; its stereoscopy (the geometry shader that draws two
 eyes, Depth and Convergence) is theirs.
''')
