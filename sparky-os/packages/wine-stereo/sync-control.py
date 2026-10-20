#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Keep Wine's source-control generator consistent with retained build inputs.

Run after lean.debian_prepare and dependency pinning in a disposable Wine export.
The upstream check-control guard stays enabled and checks the complete result.
"""
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
control = (root / 'debian/control').read_text()
template_path = root / 'debian/control.in'
template = template_path.read_text()
source, separator, _ = control.partition('\n\n')
old_source, old_separator, binaries = template.partition('\n\n')
if (not separator or not old_separator or not source.startswith('Source: wine\n')
        or not old_source.startswith('Source: wineVERSION\n')):
    raise SystemExit('Expected the reviewed stable Wine control template')
source = source.replace('Source: wine\n', 'Source: wineVERSION\n', 1)
template_path.write_text(source + '\n\n' + binaries)
subprocess.run(['sh', 'debian/scripts/check-control'], cwd=root, check=True)
print('Wine control generator and retained Build-Depends agree')
