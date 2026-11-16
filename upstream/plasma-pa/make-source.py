#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the accepted stream-visibility change on Debian's source, then add Lean Code."""
import os
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys

recipe=Path(__file__).resolve().parent
repo=recipe.parents[1]
toolkit=repo/'sparky-os'
base=Path(sys.argv[1]).resolve()
assert hashlib.sha256(base.read_bytes()).hexdigest() == '9217c853f0916f31ee7922d5b53271a4af572a602c9ee81f9f31142c88f2d09b'
work=Path(sys.argv[2]).resolve()
assert os.environ['SOURCE_DATE_EPOCH'].isdigit()
assert not work.exists(), work
work.mkdir(parents=True)
version='4:6.7.4-1+stereo3d1'
source=work/'source'
subprocess.run(['dpkg-source','-x',str(base),str(source)],check=True)
for p in base.parent.glob('plasma-pa_6.7.4.orig.tar.*'):
    shutil.copy2(p,work/p.name)
patches=source/'debian/patches'
patches.mkdir(exist_ok=True)
shutil.copy2(recipe/'patches/virtual-streams.patch',patches)
translation=toolkit/'translations/plasma-pa-virtual-streams.po.patch'
(patches/translation.name).write_text('Description: Translate virtual stream visibility labels\nAuthor: Daniel Campos Ramos\nOrigin: vendor\nForwarded: no\n\n'+translation.read_text())
series=patches/'series'
with series.open('a') as f:
    f.write('virtual-streams.patch\nplasma-pa-virtual-streams.po.patch\n')
subprocess.run(['dpkg-source','--before-build','.'],cwd=source,check=True)
# Debian's test policy stays explicit; its GUI suite needs the separate Appium rig.
rules=source/'debian/rules'
text=rules.read_text()
assert 'override_dh_auto_test:\n\t:\n' in text
text=text.replace('override_dh_auto_test:\n\t:\n',
    'override_dh_auto_test:\n\t@printf "%s\\n" "Debian disables build-time tests. The upstream applettest requires selenium-webdriver-at-spi-run, Appium, its Python driver, a private compositor and accessibility session; run the native and installed UI proofs separately."\n')
rules.write_text(text)
control=source/'debian/control'
text=control.read_text()
old=next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text=text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-'+old,1)
text=text.replace('Homepage: https://invent.kde.org/plasma/plasma-pa',
                  'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues',1)
control.write_text(text)
subprocess.run(['dch','--date',os.environ['SOURCE_DATE_RFC2822'],'--newversion',version,'--distribution','mashtabba',
    'Expose optional virtual streams in the Sound page and volume widget; repair null-client handling and recording-device selection.'],cwd=source,check=True)
subprocess.run(['python3',str(toolkit/'repo/provenance-files.py'),str(source),'virtual-streams.patch','plasma-pa-virtual-streams.po.patch'],check=True)
repro=toolkit/'repo/reproducible.py'
subprocess.run(['python3',str(repro),'normalize-tree',os.environ['SOURCE_DATE_EPOCH'],str(source)],check=True)
subprocess.run(['dpkg-source','-b','source'],cwd=work,check=True)
authored=work/'authored'
authored.mkdir()
for p in work.glob('plasma-pa_*'):
    if p.is_file(): shutil.copy2(p,authored/p.name)
lc=work/'lc'
lc.mkdir()
for p in authored.iterdir(): shutil.copy2(p,lc/p.name)
subprocess.run(['dpkg-source','-x',str(authored/'plasma-pa_6.7.4-1+stereo3d1.dsc'),str(lc/'source')],check=True)
env=dict(os.environ,PYTHONPATH=str(toolkit))
subprocess.run(['python3','-m','lean.debian_prepare',str(lc/'source'),version+'+lc1','--toolkit',str(toolkit)],env=env,check=True)
subprocess.run(['python3',str(repro),'normalize-tree',os.environ['SOURCE_DATE_EPOCH'],str(lc/'source')],check=True)
subprocess.run(['dpkg-source','-b','source'],cwd=lc,check=True)
print(lc/'plasma-pa_6.7.4-1+stereo3d1+lc1.dsc')
