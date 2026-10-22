# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Replacement for dh_builddeb, after ordinary debhelper staging and gencontrol.

Run from an extracted Debian source tree. Supply the bundled provenance helper.
Runtime, automatic dbgsym and generated HR archives all enter debian/files before
dpkg-genbuildinfo and dpkg-genchanges calculate their final checksums.
"""
import argparse
import os
from pathlib import Path
import subprocess

from . import package, release, source_tree


def link_gate(built):
    """Link and start gate (ORDER 198): the build fails, and its archives are removed, unless every
    rebuilt ELF resolves like its predecessor in SPARKY_LC_PREVIOUS_DIR (when set) and the programs
    of lean/smoke.tsv start. The runtime dependencies are installed in the build environment."""
    gated = [deb for deb in built if not deb.name.split('_')[0].endswith(('-dbgsym', '-lc-hr'))]
    try:
        release.check_link(gated, os.environ.get('SPARKY_LC_PREVIOUS_DIR') or None,
                           str(Path(release.__file__).with_name('smoke.tsv')))
    except (ValueError, OSError, subprocess.CalledProcessError):
        for deb in built:
            deb.unlink(missing_ok=True)
        raise


def build(root, provenance):
    controls = sorted(list((root / 'debian').glob('*/DEBIAN/control')) +
                      list((root / 'debian/.debhelper').glob('*/dbgsym-root/DEBIAN/control')))
    if not controls:
        raise ValueError('No staged binary controls; run after dh_gencontrol')
    built = []
    for control in controls:
        staging = control.parent.parent
        fields = package.control(staging)
        name, version, arch = package.identity(fields)
        source_tree.restore_payload(root, staging)
        subprocess.run(['bash', str(provenance), '--tree', str(staging)], check=True)
        before = set(root.parent.glob('*.deb'))
        release.build_tree(staging, root.parent)
        outputs = sorted(set(root.parent.glob('*.deb')) - before)
        built += outputs
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
    link_gate(built)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--provenance', type=Path, required=True)
    args = parser.parse_args()
    try:
        build(Path.cwd(), args.provenance.resolve())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')
