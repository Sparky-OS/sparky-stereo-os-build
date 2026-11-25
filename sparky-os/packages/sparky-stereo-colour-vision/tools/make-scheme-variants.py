#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the colour-vision variants of the edition's default look's scheme (sparky-stereo-look's Sparky Stereo Oxygen Dark,
from this tree) into data/color-schemes, with the helper's own generator: the package ships them, and the helper uses a
shipped variant only while the installed base scheme has the SHA-256 the variant records. Usage: make-scheme-variants.py"""
import importlib.machinery
import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
BASES = [PACKAGE.parent / 'sparky-stereo-look/default/color-schemes/SparkyStereoOxygenDark.colors']
loader = importlib.machinery.SourceFileLoader('helper', str(PACKAGE / 'helper/sparky-stereo-colour-vision'))
spec = importlib.util.spec_from_loader('helper', loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)
helper.SHARE = PACKAGE / 'data'
locales = tempfile.mkdtemp()   # the catalogues as the package installs them, so the variants' names are translated
for po in sorted((PACKAGE / 'po').glob('*/kcm_sparkystereo_colourvision.po')):
    mo = Path(locales) / po.parent.name / 'LC_MESSAGES' / 'kcm_sparkystereo_colourvision.mo'
    mo.parent.mkdir(parents=True)
    subprocess.run(['msgfmt', '-o', str(mo), str(po)], check=True)
os.environ['SPARKY_STEREO_COLOUR_VISION_LOCALEDIR'] = locales
for base in BASES:
    for kind, name in helper.KIND_NAMES.items():
        target = PACKAGE / 'data/color-schemes' / f'{base.stem}{helper.SUFFIX}{name}.colors'
        helper.write_variant(base, target, kind)
        print(target.name)
