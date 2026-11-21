#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""flat-index.py DIR: a flat apt repository index for the .deb files in DIR: Packages (each control paragraph with
Filename, Size, MD5sum, SHA256) and a Release with Origin "Sparky Stereo OS" and Suite stage, so the edition's pin
applies to them as in a round. Reads only (dpkg-deb -f); runs nothing from the packages."""
import hashlib, subprocess, sys
from pathlib import Path
d = Path(sys.argv[1]); paras = []
for deb in sorted(d.glob('*.deb')):
    control = subprocess.run(['dpkg-deb', '-f', str(deb)], capture_output=True, text=True, check=True).stdout.rstrip('\n')
    data = deb.read_bytes()
    paras.append(control + f"\nFilename: ./{deb.name}\nSize: {len(data)}\nMD5sum: {hashlib.md5(data).hexdigest()}\n"
                 f"SHA256: {hashlib.sha256(data).hexdigest()}\n")
(d / 'Packages').write_text('\n'.join(paras))
pk = (d / 'Packages').read_bytes()
(d / 'Release').write_text(f"Origin: Sparky Stereo OS\nLabel: lane 50f stage\nSuite: stage\nCodename: stage\n"
                           f"SHA256:\n {hashlib.sha256(pk).hexdigest()} {len(pk)} Packages\n")
print(len(paras), "packages")
