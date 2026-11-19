# Copyright 2026 Daniel Campos Ramos, GPL-3.0-or-later.
"""Canonical metadata for original components shared by both source routes."""
from pathlib import Path
import shutil
import tarfile


def fonts(source, root, archive):
    source, root, archive = map(Path, (source, root, archive))
    target = root / 'fonts'
    target.mkdir(exist_ok=True)
    paths = sorted(source.glob('*.otf'))
    if not paths:
        raise ValueError('No declared font component files')
    with tarfile.open(archive, 'w:xz') as tar:
        for path in paths:
            info = tar.gettarinfo(str(path), arcname='fonts/' + path.name)
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mode = 0o644
            info.mtime = 0
            with path.open('rb') as stream:
                tar.addfile(info, stream)
    for path in paths:
        dest = target / path.name
        if path.resolve() != dest.resolve():
            shutil.copyfile(path, dest)
        dest.chmod(0o644)
