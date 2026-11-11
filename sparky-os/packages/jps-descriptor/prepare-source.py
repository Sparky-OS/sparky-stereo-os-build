#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
"""Prepare the published KImageFormats stereo3d5 source as plain stereo3d6."""
import argparse
import email.utils
import os
from pathlib import Path
import re
import shutil
import subprocess

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
start = control.index('Build-Depends:')
end = control.index('\n\n', start)
field = control[start:end]
suffix = ', gcc, node-acorn, nodejs, perl, python3, python3-yaml'
if not field.endswith(suffix):
    raise SystemExit('The published LC dependency suffix changed')
control_path.write_text(control[:start] + re.sub(r'\n[ \t]+', ' ', field) + control[end:])
helper = recipe.parents[1] / 'repo/plain-from-lc.py'
subprocess.run(['python3', str(helper), '--build-depends-at-end', '--edition-entry',
                '--save-plan', str(source.parent / (source.name + '.preserve.json')), str(source)], check=True)
plain_control = control[:start] + field[:-len(suffix)] + control[end:]
plain_control = plain_control.replace('Build-Depends:', 'Build-Depends: qt6-tools-dev, qt6-l10n-tools,', 1)
control_path.write_text(plain_control)
patch = recipe / 'jps-descriptor.patch'
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

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {email.utils.formatdate(epoch, localtime=False)}

'''
changelog.write_text(entry + changelog.read_text())
print('Prepared plain kf6-kimageformats 6.30.0-1+stereo3d6')
