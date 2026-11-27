#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the published sources for the Steam Runtime fixes."""
import argparse
import datetime
from email.utils import format_datetime
from pathlib import Path
import shutil
import subprocess

SOURCES = {
    'gl-stereo': ('0.4.5-1+lc1', '0.4.5-2+lc1',
                  'Pass the declaration dependency with the GL interposer into Steam Runtime.'),
    'dxvk': ('2.7.1-4+stereo3d5+lc1', '2.7.1-4+stereo3d6+lc1',
             'Install prefix-local DXVK DLLs so games load them inside Steam Runtime.'),
    'wiz3d': ('0.3.1+stereo3d6+lc1', '0.3.1+stereo3d7+lc1',
              'Share the injector payload and declaration state with Steam Runtime.'),
}


def run(*command, **kwargs):
    subprocess.run(command, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name', choices=SOURCES)
    parser.add_argument('predecessor', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--epoch', type=int, required=True)
    args = parser.parse_args()
    old, new, summary = SOURCES[args.name]
    old_dsc = args.predecessor.resolve() / f'{args.name}_{old}.dsc'
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    tree = output / 'tree'
    run('dpkg-source', '-x', str(old_dsc), str(tree))
    for tarball in sorted(old_dsc.parent.glob(f'{args.name}_*.orig*.tar.*')):
        shutil.copy2(tarball, output / tarball.name)
    patch = Path(__file__).with_name(args.name + '.patch')
    if args.name == 'gl-stereo':
        series = tree / 'debian/patches/series'
        series.parent.mkdir(exist_ok=True)
        patch_name = 'pressure-vessel-preloads.patch'
        shutil.copy2(patch, series.with_name(patch_name))
        with series.open('a') as stream:
            stream.write(patch_name + '\n')
        run('dpkg-source', '--before-build', str(tree))
    else:
        run('patch', '--batch', '--fuzz=0', '-p1', '-i', str(patch.resolve()), cwd=tree)
    if args.name == 'dxvk':
        # The published source has separate orig components and no vendor.xz.
        # Remove the inherited dpkg-source entry for that absent file.
        listing = tree / 'debian/source/include-binaries'
        if listing.read_text().strip() != 'debian/vendor.xz' or (tree / 'debian/vendor.xz').exists():
            raise ValueError('Review the changed DXVK vendor input before preparing the source')
        listing.unlink()

    changelog = tree / 'debian/changelog'
    timestamp = format_datetime(datetime.datetime.fromtimestamp(args.epoch, datetime.timezone.utc))
    heading = (f'{args.name} ({new}) testing; urgency=medium\n\n'
               f'  * {summary}\n\n'
               f' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {timestamp}\n\n')
    changelog.write_text(heading + changelog.read_text())
    toolkit = Path(__file__).resolve().parents[2]
    run('python3', str(toolkit / 'repo/reproducible.py'), 'normalize-tree', str(args.epoch), str(tree))
    run('dpkg-source', '-b', 'tree', cwd=output)


if __name__ == '__main__':
    main()
