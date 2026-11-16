#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read the supplied Debian source's changelog date without unpacking its tree."""
from pathlib import Path
import sys
import tarfile
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'repo'))
from reproducible import parse_trailer
with tarfile.open(sys.argv[1]) as archive:
    changelog=archive.extractfile('debian/changelog')
    if changelog is None: raise ValueError('Debian archive has no changelog')
    print(parse_trailer(changelog.read().decode()))
