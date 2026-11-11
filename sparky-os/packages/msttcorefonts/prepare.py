#!/usr/bin/env python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Adapt the verified plain Debian 3.8.1 source; never imports a +lc1 tree."""
import email.utils
from datetime import datetime, timezone
import os
import re
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
recipe = Path(__file__).resolve().parent
changelog = root / 'debian/changelog'
assert changelog.read_text().startswith('msttcorefonts (3.8.1)'), 'expected plain Debian msttcorefonts 3.8.1'
assert not (root / '.sparky-lc').exists(), 'plain source required'
subprocess.run(['patch', '--batch', '--forward', '-p1', '-i', str(recipe / 'ubuntu-eula.patch')], cwd=root, check=True)
subprocess.run(['patch', '--batch', '--forward', '-p1', '-i', str(recipe / 'edition.patch')], cwd=root, check=True)
control = root / 'debian/control'
text = control.read_text()
text = re.sub(r'^Maintainer: (.+)$',
              r'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\n'
              r'XSBC-Original-Maintainer: \1\n'
              r'Homepage: https://sparkylinux.org\n'
              r'Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', text, count=1, flags=re.M)
text = text.replace('Multi-Arch: foreign\n', 'Multi-Arch: foreign\n'
                    'XB-Sparky-Install-Download-Size: 3934864\n'
                    'XB-Sparky-Install-Download-Source: https://downloads.sourceforge.net/corefonts/\n')
control.write_text(text)
date = email.utils.format_datetime(datetime.fromtimestamp(int(os.environ['SOURCE_DATE_EPOCH']), timezone.utc))
changelog.write_text('msttcorefonts (3.8.1+stereo3d2) unstable; urgency=medium\n\n'
                    '  * Carry Michael Vogt\'s Ubuntu EULA presentation with default-false consent.\n'
                    '  * Download during target installation only; declare size and source to apt.\n'
                    '  * Say refusal and provide retry guidance for incomplete configuration.\n\n'
                    ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n'
                    + changelog.read_text())
copyright_file = root / 'debian/copyright'
copyright_file.write_text(copyright_file.read_text() + '\n'
    'Sparky Stereo OS, Daniel Ramos\'s (Capitain Jack) edition of SparkyLinux\n'
    '(https://sparkylinux.org, by Paweł "pavroo" Pijanowski).\n'
    'Edition packaging additions: Copyright 2026 Daniel Ramos (Capitain Jack), GPL-2-or-later.\n'
    'EULA presentation adapted from Ubuntu msttcorefonts, Michael Vogt, GPL-2-or-later.\n'
    'The EULA text is Copyright Microsoft Corporation; no font data is redistributed here.\n')
