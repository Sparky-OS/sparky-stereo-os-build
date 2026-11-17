# SPDX-License-Identifier: GPL-2.0-only
"""Where a kernel build's scratch (SPARKY_MIGRATION_WORK) may go (ORDER 638): any local solid-state disk with room,
never a hard disk or a network mount, with the house floors only: 1 GiB on the root file system, 2 GiB on another disk.

    floor_gib(PATH)   the house floor of the disk that holds PATH
    check(PATH)       SystemExit unless PATH is on a local solid-state disk
"""
import os
from pathlib import Path


def floor_gib(path):
    return 1 if os.stat(path).st_dev == os.stat('/').st_dev else 2


def check(path):
    device = os.stat(path).st_dev
    block = Path(f'/sys/dev/block/{os.major(device)}:{os.minor(device)}').resolve()
    rotational = next((p / 'queue/rotational' for p in (block, block.parent) if (p / 'queue/rotational').is_file()), None)
    if rotational is None:
        raise SystemExit(f'{path}: not on a local disk (a network or virtual mount); build scratch goes on a solid-state disk')
    if rotational.read_text().strip() != '0':
        raise SystemExit(f'{path}: on a hard disk ({rotational.parent.parent.name}); build scratch goes on a solid-state disk')
