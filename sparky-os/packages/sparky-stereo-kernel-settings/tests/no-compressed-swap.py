#!/usr/bin/python3
"""Check opt-in swap policy with the publication gate, in a disposable container.

No arguments checks the installed package's files and metadata. --deb checks
an archive without running its programs. Retiring helpers are allowed; setup
or relations that install compressed swap or cap the person's choice refuse.
"""
import argparse
import importlib.util
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

PACKAGE = 'sparky-stereo-kernel-settings'
GATE = Path(__file__).resolve().parents[3] / 'iso-build/zram-check.py'
spec = importlib.util.spec_from_file_location('zram_gate', GATE)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def installed(root):
    control = subprocess.check_output(['dpkg-query', '-s', PACKAGE], text=True)
    if 'Status: install ok installed\n' not in control:
        raise ValueError(f'{PACKAGE} must be installed')
    info = root / 'var/lib/dpkg/info'
    info.mkdir(parents=True)
    (info.parent / 'status').write_text(control)
    files = subprocess.check_output(['dpkg-query', '-L', PACKAGE], text=True).splitlines()
    for name in files:
        source = Path(name)
        if source.is_dir() and not source.is_symlink():
            continue
        target = root / name.lstrip('/')
        if not target.parent.resolve().is_relative_to(root):
            raise ValueError(f'{name}: parent leaves the fixture root')
        if source.is_symlink():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(os.readlink(source))
        elif source.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for script in ('preinst', 'postinst', 'prerm', 'postrm', 'triggers'):
        source = Path('/var/lib/dpkg/info') / f'{PACKAGE}.{script}'
        if source.is_file():
            shutil.copy2(source, info / source.name)
    return gate.check_image(root, [])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deb', type=Path, help='check this package archive instead of the installed package')
    args = parser.parse_args()
    if args.deb:
        findings, notes, error = gate.check_deb(args.deb)
        return gate.report(findings, [error] if error else [], str(args.deb), notes)
    with tempfile.TemporaryDirectory(prefix='swap-policy-') as folder:
        return gate.report(*installed(Path(folder)))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'Cannot check compressed-swap defaults: {error}')
