#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
"""check-payload-build-records.py DEB...: a package's payload holds no folder of the build's Lean Code records.
lean.source_tree keeps its native pass's report and authored copies in .sparky-lc/ at the top of the build tree; a
package that installs a copy of that tree (DKMS sources) must leave it out, or it ships the report of the toolkit that
built it (ORDER 311). Prints each archive's verdict; exits 1 if any payload has such a path."""
import os
import subprocess
import sys

bad = 0
for deb in sys.argv[1:]:
    names = subprocess.run(['dpkg-deb', '--fsys-tarfile', deb], stdout=subprocess.PIPE, check=True).stdout
    listing = subprocess.run(['tar', '-t'], input=names, stdout=subprocess.PIPE, check=True).stdout.decode().splitlines()
    found = [n for n in listing if '.sparky-lc' in n.rstrip('/').split('/')]
    print(f'{os.path.basename(deb)}: ' + (f'FAIL, {len(found)} paths under .sparky-lc ({found[0]})' if found else 'no build records'))
    bad += bool(found)
sys.exit(1 if bad else 0)
