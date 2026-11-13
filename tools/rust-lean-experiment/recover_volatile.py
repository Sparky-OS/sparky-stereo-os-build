#!/usr/bin/env python3
"""Retire only this kit's volatile Podman state after a detected host reboot."""
import os
from pathlib import Path
import shutil
import sys


def recover(root):
    root=Path(root).resolve()
    if not (root/'plan.json').is_file() or not (root/'runtime').is_dir():
        raise RuntimeError('not an initialized experiment kit')
    if (root/'runtime').is_symlink():raise RuntimeError('runtime must not be a symbolic link')
    targets=[root/'runtime'/n for n in ('runroot','engine-tmp')]
    if any(p.is_symlink() for p in targets):raise RuntimeError('volatile engine directory must not be a symbolic link')
    owner=root.stat()
    for p in targets:
        if p.exists():shutil.rmtree(p)
        p.mkdir(mode=0o700)
        if os.geteuid()==0:os.chown(p,owner.st_uid,owner.st_gid)
    print('Retired kit runroot and engine-tmp after a detected reboot; image storage and results retained')


if __name__=='__main__':recover(sys.argv[1])
