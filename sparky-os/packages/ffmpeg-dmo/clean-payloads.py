#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Remove only generated binary-package payloads before resuming qualification."""
from pathlib import Path
import re
import shutil

debian = Path.cwd() / 'debian'
for name in re.findall(r'^Package: ([a-z0-9][a-z0-9+.-]*)$', (debian / 'control').read_text(), re.M):
    payload = debian / name
    if payload.is_dir() and not payload.is_symlink():
        shutil.rmtree(payload)
    for generated in (debian / (name + '-lc-hr'), debian / '.debhelper' / name / 'dbgsym-root'):
        if generated.is_dir() and not generated.is_symlink():
            shutil.rmtree(generated)
