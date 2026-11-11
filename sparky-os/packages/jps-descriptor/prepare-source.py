#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
"""Prepare the published KImageFormats stereo3d5 source as plain stereo3d7."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
args = parser.parse_args()
source = args.source.resolve()
recipe = Path(__file__).resolve().parent
changelog = source / 'debian/changelog'
text = changelog.read_text()
if not text.startswith('kf6-kimageformats (6.30.0-1+stereo3d5+lc1)'):
    raise SystemExit('Expected the published 6.30.0-1+stereo3d5+lc1 source')
epoch = int(os.environ['SOURCE_DATE_EPOCH'])
control_path = source / 'debian/control'
control = control_path.read_text()
# This historical source appends the six LC dependencies to a folded field.
# The strict recovery helper accepts that form on one line; reflow only this field.
match = re.search(r'^Build-Depends:[^\n]*(?:\n[ \t]+[^\n]*)*', control, re.M)
if match is None:
    raise SystemExit('No Build-Depends field')
start, end = match.span()
field = match.group()
suffix = ', gcc, node-acorn, nodejs, perl, python3, python3-yaml'
if not field.endswith(suffix):
    raise SystemExit('The published LC dependency suffix changed')
control_path.write_text(control[:start] + re.sub(r'\n[ \t]+', ' ', field) + control[end:])
carried_plan = source.parent / (source.name + '.preserve.json')
plain_command = ['python3', str(recipe.parents[1] / 'repo/plain-from-lc.py'), '--save-plan', str(carried_plan)]
plain_command += ['--build-depends-at-end', '--edition-entry', str(source)]
subprocess.run(plain_command, check=True)
sys.path.insert(0, str(recipe.parents[1] / 'repo'))
import reproducible
plain_control = control[:start] + field[:-len(suffix)] + control[end:]
plain_control = plain_control.replace('Build-Depends:', 'Build-Depends: qt6-tools-dev, qt6-l10n-tools,', 1)
plain_control = plain_control.replace('Build-Depends:', 'Build-Depends: libstereo-policy-dev (>= 1.17.5),', 1)
# The common codec is Qt-free and needs no dependency on the picture library or its image plugins.
plain_control = re.sub(r'(Package: kimageformat6-plugins\n.*?^Depends:)', r'\1 libstereo-policy1 (>= 1.17.5),', plain_control, flags=re.M | re.S)
control_path.write_text(plain_control)
for name in ('jps-descriptor.patch', 'shared-jpeg-codec.patch'):
    patch = recipe / name
    shutil.copyfile(patch, source / 'debian/patches' / patch.name)
    with (source / 'debian/patches/series').open('a') as stream:
        stream.write(patch.name + '\n')
subprocess.run(['dpkg-source', '--before-build', str(source)], check=True)
entry = f'''kf6-kimageformats (6.30.0-1+stereo3d6) unstable; urgency=medium

  * Write the VRex APP3 JPS descriptor for every supported layout, with
    explicit flags, eye order, separation, mono display and ASCII comments.
  * Report descriptor fields without changing reader pixels. Refuse
    unsupported layouts and invalid fields before writing, with messages
    in all ten edition languages. Test every write through an independent
    segment parser and a reader round trip.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {reproducible.rfc2822(epoch)}

'''
codec_entry = f'''kf6-kimageformats (6.30.0-1+stereo3d7) unstable; urgency=medium

  * Use libstereo-policy's common JPS and MPF codec for image readers and
    writers, shared with metadata-only picture correction saves. Preserve
    the existing writer behavior and complete carried patch series.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {reproducible.rfc2822(epoch)}

'''
changelog.write_text(codec_entry + entry + changelog.read_text())
reproducible.normalize_tree(source, epoch)
if carried_plan.exists():
    print('Pass to lean.debian_prepare --preserve-plan:', carried_plan)
print('Prepared plain kf6-kimageformats 6.30.0-1+stereo3d7')
