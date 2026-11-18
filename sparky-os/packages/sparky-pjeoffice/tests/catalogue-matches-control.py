#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""The install-time download the control file declares (apt and Stereo APTus say it before anything is fetched) is the one the catalogue reviewed:
same size, same address. Reads debian/control and catalogue/catalogue.json of the recipe, or the control file of a built .deb.
Usage: catalogue-matches-control.py [RECIPE_DIR | PACKAGE.deb]"""
import json, re, subprocess, sys
from pathlib import Path

target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
if target.suffix == '.deb':
    control = subprocess.run(['dpkg-deb', '-f', str(target)], capture_output=True, text=True, check=True).stdout
    prefix = ''
    catalogue = json.loads(subprocess.run(['sh', '-c', "dpkg-deb --fsys-tarfile '%s' | tar -xO ./usr/share/sparky-pjeoffice/catalogue.json" % target],
                                          capture_output=True, text=True, check=True).stdout)
else:
    control = (target / 'debian/control').read_text()
    prefix = 'XB-'
    catalogue = json.loads((target / 'catalogue/catalogue.json').read_text())
entry = catalogue['versions'][catalogue['current']]
size = re.search(r'(?m)^%sSparky-Install-Download-Size:\s*(\d+)$' % prefix, control)
source = re.search(r'(?m)^%sSparky-Install-Download-Source:\s*(\S+)$' % prefix, control)
failures = []
if not size or int(size.group(1)) != entry['size']:
    failures.append('size: control %s, catalogue %s' % (size and size.group(1), entry['size']))
if not source or source.group(1) != entry['url']:
    failures.append('source: control %s, catalogue %s' % (source and source.group(1), entry['url']))
if not entry['url'].startswith('https://') or not re.fullmatch(r'[0-9a-f]{64}', entry['sha256']):
    failures.append('the catalogue entry is not an https address with a SHA-256')
for line in failures:
    print('FAIL ' + line)
print('RESULT: ' + ('FAIL' if failures else 'PASS') + ' (control and catalogue agree on %d bytes from %s)' % (entry['size'], entry['url']))
sys.exit(1 if failures else 0)
