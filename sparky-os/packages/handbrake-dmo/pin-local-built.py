#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Keep the exact built library cohort selected in this isolated build."""
from pathlib import Path
import subprocess
import sys

rows = []
for archive in sys.argv[1:]:
    fields = subprocess.check_output(['dpkg-deb', '-f', archive, 'Package', 'Version'], text=True)
    fields = dict(line.split(': ', 1) for line in fields.splitlines())
    rows.append(f"Package: {fields['Package']}\nPin: version {fields['Version']}\nPin-Priority: 1002\n")
Path('/etc/apt/preferences.d/hb742-local-built').write_text('\n'.join(rows))
