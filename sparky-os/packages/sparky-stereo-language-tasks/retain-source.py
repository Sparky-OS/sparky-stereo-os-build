#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Retain verified upstream inputs and regenerate catalogues in offline source builds."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from catalogues import PIN, verify

out, source_dir, version = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve(), sys.argv[3]
verify(source_dir)
name = 'sparky-stereo-language-tasks'
with tempfile.TemporaryDirectory(prefix='language-source-', dir=out) as temporary:
    work = Path(temporary)
    source = work / (name + '-' + version)
    subprocess.run(['dpkg-source', '-x', str(out / (name + '_' + version + '.dsc')), str(source)], check=True)
    (source / 'upstream').mkdir()
    for filename in PIN['files']:
        shutil.copyfile(source_dir / filename, source / 'upstream' / filename)
    builder = source / 'build.py'
    text = builder.read_text()
    marker = '    before = set(root.parent.glob("*.deb"))\n'
    if text.count(marker) != 1:
        raise ValueError('Standalone source builder changed: catalogue hook location is ambiguous')
    hook = ('    subprocess.run([sys.executable, str(root / "authoring/catalogues.py"), '
            '"--source-dir", str(root / "upstream"), "--tree", str(staging)], check=True)\n')
    builder.write_text(text.replace(marker, hook + marker))
    with (source / 'README.source').open('a') as stream:
        stream.write('\nupstream/ retains Debian tasksel 3.92 unchanged, with its descriptor and\n'
                     'archive verified by authoring/tasksel-source.json and the descriptor\n'
                     'component checksum. Every binary rebuild regenerates both gettext\n'
                     'domains from authoring/po and these upstream inputs, without network.\n'
                     'Original translator credits remain in Debian\'s source files.\n')
    sys.path.insert(0, str(source / 'release-toolkit'))
    from lean.standalone import normalize_modes
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'repo'))
    import reproducible
    stamp = int(os.environ['SOURCE_DATE_EPOCH'])
    normalize_modes(source)
    reproducible.normalize(source, stamp)
    subprocess.run(['dpkg-source', '-b', str(source)], cwd=work, check=True)
    for suffix in ('dsc', 'tar.xz'):
        filename = name + '_' + version + '.' + suffix
        shutil.copyfile(work / filename, out / filename)
