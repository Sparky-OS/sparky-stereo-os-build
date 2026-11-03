#!/usr/bin/python3
"""Check an installed package's payload and metadata. Run inside a container."""
import subprocess
import sys
from pathlib import Path

package = 'sparky-stereo-kernel-settings'
files = subprocess.check_output(['dpkg-query', '-L', package], text=True).splitlines()
bad = [p for p in files if 'zram' in p.lower() or 'zswap' in p.lower()]
depends = subprocess.check_output(['dpkg-query', '-W', '-f=${Depends}', package], text=True)
conflicts = subprocess.check_output(['dpkg-query', '-W', '-f=${Conflicts}', package], text=True)
checks = {
    'no compressed-swap unit, config or helper in package': not bad,
    'no generator dependency': 'systemd-zram-generator' not in depends,
    'generator conflict': 'systemd-zram-generator' in conflicts,
    'tools conflict': 'zram-tools' in conflicts,
}
for name, ok in checks.items():
    print(('PASS ' if ok else 'FAIL ') + name)
for path in bad:
    print('unexpected installed path:', path)
sys.exit(not all(checks.values()))
