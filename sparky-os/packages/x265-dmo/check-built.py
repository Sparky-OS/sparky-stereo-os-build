#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Record only this source version, without relabelling an earlier experiment."""
from pathlib import Path
import os
import subprocess
import sys
source = Path(sys.argv[1]).resolve()
version = subprocess.check_output(['dpkg-parsechangelog', '-SVersion'], cwd=source, text=True).strip()
archives = [str(p) for p in source.parent.glob('*.deb') if
            subprocess.check_output(['dpkg-deb', '-f', str(p), 'Version'], text=True).strip() == version]
assert archives
subprocess.run([sys.executable, '-m', 'lean.release', 'check-debs', *archives], check=True,
               env=os.environ | {'PYTHONPATH': str(source / 'debian/sparky-lean-toolkit')})
