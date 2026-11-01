#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Append the reviewed CPU refresh series to the published QEMU Debian source."""
import argparse
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
BASE = '1:11.1.2+ds-3+stereo3d6+lc1'
NEXT = '1:11.1.2+ds-3+stereo3d7+lc1'
PATCHES = (
    '0009-spice-refresh-static-stereo-source.patch',
    '0010-spice-refresh-comment-style.patch',
    '0011-spice-check-full-refresh-allocation.patch',
)


def main(root):
    root = root.resolve()
    changelog = root / 'debian/changelog'
    old = changelog.read_text()
    if not old.startswith(f'qemu ({BASE}) '):
        raise ValueError('Review a changed published QEMU base before integrating')
    series = root / 'debian/patches/series'
    original = series.read_text()
    names = [line.split()[0] for line in original.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    if len(names) != 37 or len(set(names)) != 37:
        raise ValueError('Expected the 37-patch published series')
    additions = ['stereo3d/' + name for name in PATCHES]
    if any((root / 'debian/patches' / name).exists() for name in additions):
        raise ValueError('Refusing to replace a previously integrated patch')
    for name in PATCHES:
        if not (HERE / 'patches' / name).is_file():
            raise ValueError(f'Missing reviewed patch {name}')
    for name, destination in zip(PATCHES, additions):
        target = root / 'debian/patches' / destination
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(HERE / 'patches' / name, target)
    series.write_text(original.rstrip('\n') + '\n' + '\n'.join(additions) + '\n')
    entry = f'''qemu ({NEXT}) UNRELEASED; urgency=medium

  * Refresh the current CPU surface after a stereo metadata change, including
    OFF, even when its pixels match the mirror. Preserve duplicate metadata
    suppression and ordinary dirty updates.
  * Check the full-refresh bitmap allocation size before multiplying it.
  * Carry the three reviewed downstream commits together as DEP-3 patches;
    retain the published native-sample patch and Debian's existing fixes.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {format_datetime(datetime.now(timezone.utc))}

'''
    changelog.write_text(entry + old)
    print(f'Prepared patch integration {BASE} -> {NEXT}; package build pending')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    main(args.source)
