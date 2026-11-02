#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
"""Require configured ZFS tools, DKMS and usable module files for every image kernel.

Run inside the image chroot: zfs-check.py [ROOT].
ROOT is also accepted for isolated fixtures; no module is loaded or pool opened.
"""
import re
import subprocess
import sys
from pathlib import Path


def check(root):
    errors = []
    try:
        status = (root / 'var/lib/dpkg/status').read_text()
        packages = {}
        for stanza in status.split('\n\n'):
            fields = dict(re.findall(r'^([A-Za-z-]+): (.*)$', stanza, re.M))
            if fields.get('Status') == 'install ok installed':
                packages[fields.get('Package')] = fields.get('Version', '')
    except (OSError, UnicodeError) as error:
        return [f'cannot read installed package status: {error}']
    for name in ('zfs-dkms', 'zfsutils-linux', 'zfs-zed'):
        if not packages.get(name):
            errors.append(f'{name} is missing or not configured')
    kernels = sorted(p.name.removeprefix('vmlinuz-')
                     for p in (root / 'boot').glob('vmlinuz-*') if p.is_file())
    if not kernels:
        errors.append('no kernel image found in /boot')
    for kernel in kernels:
        if not packages.get(f'linux-headers-{kernel}'):
            errors.append(f'{kernel}: matching headers are missing or not configured')
        for module in ('spl', 'zfs'):
            command = ['modinfo', '-b', str(root), '-k', kernel, '-F', 'vermagic', module]
            try:
                result = subprocess.run(command, text=True, capture_output=True, check=True)
                fields = result.stdout.split()
                if not fields or fields[0] != kernel:
                    errors.append(f'{kernel}: {module} module vermagic is {result.stdout.strip()!r}')
            except (OSError, subprocess.CalledProcessError) as error:
                detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
                errors.append(f'{kernel}: cannot inspect {module} module: {detail}')
    return errors


def main():
    if len(sys.argv) > 2:
        sys.exit('usage: zfs-check.py [ROOT]')
    errors = check(Path(sys.argv[1] if len(sys.argv) == 2 else '/'))
    if errors:
        print('ZFS image validation failed:', file=sys.stderr)
        for error in errors:
            print(f'  {error}', file=sys.stderr)
        print('Install the edition ZFS packages and matching headers, complete DKMS for every image kernel, and rerun validation before packing.', file=sys.stderr)
        return 1
    print('ZFS image validation passed: packages configured and spl/zfs modules match every image kernel.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
