#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Refresh a successor against the exact published source, retaining its quilt series."""
import email.utils
import json
import os
import re
from pathlib import Path
import shutil
import subprocess

import argparse
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('input',type=Path);ap.add_argument('out',type=Path);ap.add_argument('toolkit',type=Path)
args=ap.parse_args()
recipe=Path(__file__).resolve().parent
build=args.toolkit.resolve()
epoch=int(os.environ['SOURCE_DATE_EPOCH'])
work=args.out.resolve();work.mkdir(parents=True,exist_ok=True)
assert not list(work.iterdir()),'source output must be empty'
base=work/'published';root=work/'successor'
source=args.input.resolve()/'kde-spectacle_6.7.4-1+stereo3d2+lc1.dsc'
subprocess.run(['dpkg-source','--no-copy','-x',str(source),str(base)],check=True)
for path in source.parent.glob('kde-spectacle_6.7.4.orig*'):shutil.copyfile(path,work/path.name)
shutil.copytree(base,root)
control_path = root / 'debian/control'
control_text = control_path.read_text()
# The older descriptor folds this field; the checked lc undo helper accepts one line.
control_text = re.sub(r'^Build-Depends:.*(?:\n[ \t]+.*)*', lambda m: ' '.join(line.strip() for line in m.group().splitlines()), control_text, count=1, flags=re.M)
control_path.write_text(control_text)
subprocess.run(['python3', str(build/'repo/plain-from-lc.py'), '--build-depends-at-end', '--edition-entry', '--save-plan', str(work/'preserve-plan.json'), str(root)], check=True)
for path in (recipe/'overlay-stereo3d3/patches').iterdir():
    shutil.copyfile(path,root/'debian/patches'/path.name)
series=('order772-capture.patch','spectacle-2d-export-eye.po.patch','spectacle-monitor-capture.po.patch','order772-translations.patch')
with (root/'debian/patches/series').open('a') as stream:stream.write(''.join(name+'\n' for name in series))
binary_files=[]
for path in (recipe/'source-files').rglob('*'):
    if path.is_file():
        rel=path.relative_to(recipe/'source-files');target=root/rel
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target);binary_files.append(str(rel))
subprocess.run(['dpkg-source','--before-build',str(root)],check=True)
config=json.loads((recipe/'translations.json').read_text())
for language in config['translations']:
    subprocess.run(['msgfmt','--check','-o','/dev/null',str(root/'po'/language/'spectacle.po')],check=True)
control=root/'debian/control'
s=control.read_text().replace('Build-Depends:', 'Build-Depends: libstereo-layer-dev (>= 1.10),',1).replace('kimageformat6-plugins (>= 6.30.0-1+stereo3d1)','kimageformat6-plugins (>= 6.30.0-1+stereo3d7)')
control.write_text(s)
if binary_files:(root/'debian/source/include-binaries').write_text('\n'.join(binary_files)+'\n')
changelog=root/'debian/changelog'
changelog.write_text('kde-spectacle (4:6.7.4-1+stereo3d3) unstable; urgency=high\n\n'
    '  * Complete accepted ORDER 180 monitor choices and selected-eye exports.\n'
    '  * Follow screenshot output mode in every capture path; default 3D to MPO.\n'
    '  * Crop both eye rectangles and retain mono monitors in explicit 3D views.\n'
    '  * Carry upstream capture/save fixes with their original author credit.\n'
    '  * Add Spanish and translate the new capture choices in all ten languages.\n\n'
    ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+email.utils.formatdate(epoch,usegmt=True).replace('GMT','+0000')+'\n\n'+changelog.read_text())
subprocess.run(['python3','-m','lean.debian_prepare',str(root),'4:6.7.4-1+stereo3d3+lc1','--toolkit',str(build),
    '--preserve-plan',str(work/'preserve-plan.json'),
    '--preserve-source','src/*.h','Qt moc and qmltyperegistrar consume declarations; retain authored generator inputs.'],
    env={**os.environ,'PYTHONPATH':str(build)},check=True)
# QML is outside the native C/C++ projection walk and remains authored automatically.
import sys
sys.path.insert(0, str(build / 'repo'))
from reproducible import pack
pack(str(work), 'successor', epoch)
print('Prepared and packed successor:', root)
