#!/usr/bin/env python3
# Sparky Stereo OS: checks that an sview package carries one output, Stereo KWin's (ORDER 312).
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Stereo KWin's outputs convert the declared side-by-side pair for every display, so the edition's sView
# installs no output module of its own: no other libStOut*.so, none of their shaders or language files,
# and no OpenVR (the distorted headset output was its only user).
# Usage: check-one-output.py SVIEW.deb    (exit 0: one output; 1: other outputs found)
import subprocess
import sys

deb = sys.argv[1]
files = [line.split()[-1].removeprefix('./') for line in
         subprocess.run(['dpkg-deb', '-c', deb], check=True, capture_output=True, text=True).stdout.splitlines()]
depends = subprocess.run(['dpkg-deb', '-f', deb, 'Version', 'Depends'], check=True, capture_output=True,
                         text=True).stdout
modules = sorted(f.rsplit('/', 1)[1] for f in files if '/libStOut' in f and f.endswith('.so'))
others = [m for m in modules if m != 'libStOutStereoKWin.so']
shaders = sorted(f for f in files if '/shaders/StOut' in f)
languages = sorted(f for f in files if '/lang/' in f and f.rsplit('/', 1)[1].startswith('StOut'))
openvr = 'libopenvr' in depends
print(depends.strip())
print('output modules:', ' '.join(modules) or 'none')
print('other output modules:', len(others), ' '.join(others))
print('their shaders:', len(shaders))
print('their language files:', len(languages))
print('OpenVR in Depends:', 'yes' if openvr else 'no')
ok = modules == ['libStOutStereoKWin.so'] and not shaders and not languages and not openvr
print('PASS: one output, Stereo KWin' if ok else 'FAIL: the package drives displays itself')
sys.exit(0 if ok else 1)
