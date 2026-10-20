# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Replacement for dh_builddeb, after ordinary debhelper staging and gencontrol.

Run from an extracted Debian source tree. Supply the bundled provenance helper.
Runtime, automatic dbgsym and generated HR archives all enter debian/files before
dpkg-genbuildinfo and dpkg-genchanges calculate their final checksums.
"""
import argparse
from pathlib import Path
import subprocess

from . import package, release, source_tree


def build(root, provenance):
    controls = sorted(list((root / 'debian').glob('*/DEBIAN/control')) +
                      list((root / 'debian/.debhelper').glob('*/dbgsym-root/DEBIAN/control')))
    if not controls:
        raise ValueError('No staged binary controls; run after dh_gencontrol')
    for control in controls:
        staging = control.parent.parent
        fields = package.control(staging)
        name, version, arch = package.identity(fields)
        source_tree.restore_payload(root, staging)
        subprocess.run(['bash', str(provenance), '--tree', str(staging)], check=True)
        before = set(root.parent.glob('*.deb'))
        release.build_tree(staging, root.parent)
        outputs = sorted(set(root.parent.glob('*.deb')) - before)
        files = root / 'debian/files'
        entries = files.read_text().splitlines() if files.exists() else []
        prefix = f'{name}_{version.split(":", 1)[-1]}_{arch}.'
        old_auto = any(line.split()[0].startswith(prefix) and 'automatic=yes' in line for line in entries)
        entries = [line for line in entries if not line.split()[0].startswith(prefix)]
        files.write_text(''.join(line + '\n' for line in entries))
        for deb in outputs:
            is_hr = deb.name.startswith(name + '-lc-hr_')
            section = 'doc' if is_hr else fields.get('section', 'libs')
            subprocess.run(['dpkg-distaddfile', deb.name, section, fields.get('priority', 'optional')], cwd=root, check=True)
            if is_hr or old_auto or name.endswith('-dbgsym'):
                entries = files.read_text().splitlines()
                files.write_text(''.join(line + (' automatic=yes' if line.split()[0] == deb.name and 'automatic=yes' not in line else '') + '\n' for line in entries))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provenance', type=Path, required=True)
    args = parser.parse_args()
    try:
        build(Path.cwd(), args.provenance.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')
