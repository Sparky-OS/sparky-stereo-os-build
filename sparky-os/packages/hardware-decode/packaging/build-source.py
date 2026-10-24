#!/usr/bin/env python3
"""Prepare a successor to the signed published source, retaining its LC pipeline."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('package')
p.add_argument('work', type=Path)
p.add_argument('published', type=Path)
p.add_argument('toolkit', type=Path)
p.add_argument('--libplacebo-source', type=Path)
a = p.parse_args()
here = Path(__file__).resolve().parent
packages = here.parent.parent
versions = json.loads((here/'versions.json').read_text())
version = versions[a.package]
work = a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
source = work/'source'
if source.exists():
    raise SystemExit('Use a fresh job directory')
if a.package == 'media-gpu-route':
    shutil.copytree(packages/a.package, source,
                    ignore=shutil.ignore_patterns('.git', '__pycache__', 'obj-*', '.debhelper', 'files', '*.substvars'))
    subprocess.run(['python3', '-m', 'lean.debian_prepare', str(source), version,
                    '--toolkit', str(a.toolkit)], check=True,
                   env=os.environ | {'PYTHONPATH': str(a.toolkit)})
else:
    if a.package == 'libplacebo-dmo':
        if not a.libplacebo_source:
            p.error('--libplacebo-source is required')
        directory = a.libplacebo_source
        dsc = directory/'libplacebo-dmo_7.360.1-dmo1.dsc'
    else:
        stanzas = (a.published/'dists/mashtabba/main/source/Sources').read_text().split('\n\n')
        entries = []
        for stanza in stanzas:
            fields = dict(line.split(': ', 1) for line in stanza.splitlines()
                          if ': ' in line and not line.startswith(' '))
            if fields.get('Package') == a.package:
                entries.append((stanza, fields))
        assert len(entries) == 1, (a.package, len(entries))
        stanza, fields = entries[0]
        directory = a.published/fields['Directory']
        dscs = [line.split()[-1] for line in stanza.split('Checksums-Sha256:\n', 1)[1].split('\nFiles:', 1)[0].splitlines()
                if line.strip() and line.split()[-1].endswith('.dsc')]
        assert len(dscs) == 1
        dsc = directory/dscs[0]
    shutil.copy2(dsc, work/dsc.name)
    text = dsc.read_text().split('Checksums-Sha256:\n', 1)[1].split('\nFiles:', 1)[0]
    for line in text.splitlines():
        if not line.startswith(' '):
            break
        digest, size, filename = line.split()
        original = directory/filename
        assert original.stat().st_size == int(size)
        assert hashlib.sha256(original.read_bytes()).hexdigest() == digest
        shutil.copy2(original, work/filename)
    subprocess.run(['dpkg-source', '-x', str(work/dsc.name), str(source)], check=True)
    (work/'predecessor.json').write_text(json.dumps({'dsc': dsc.name, 'sha256': hashlib.sha256(dsc.read_bytes()).hexdigest()}, indent=2)+'\n')
    args = ['python3', str(here.parent/'prepare.py'), a.package, str(source), '--version', version.removesuffix('+lc1') if a.package == 'libplacebo-dmo' else version]
    if a.package != 'libplacebo-dmo':
        args += ['--published-lc']
    if a.package in ('mlt', 'vlc', 'qt6-multimedia'):
        args += ['--ffmpeg-min-version', versions['ffmpeg-dmo'], '--gpu-route-min-version', versions['media-gpu-route']]
    if a.package == 'mpv-dmo':
        args += ['--libplacebo-min-version', versions['libplacebo-dmo'],
                 '--gpu-route-min-version', versions['media-gpu-route']]
    if (here/'entries'/(a.package + '.txt')).is_file():
        args += ['--entry', str(here/'entries'/(a.package + '.txt'))]
    if a.package == 'kdenlive':
        args += ['--mlt-min-version', versions['mlt']]
    subprocess.run(args, check=True)
    if a.package == 'libplacebo-dmo':
        # prepare.py created the authored entry; the pipeline advances to lc1.
        subprocess.run(['python3', '-m', 'lean.debian_prepare', str(source), version,
                        '--toolkit', str(a.toolkit)], check=True,
                       env=os.environ | {'PYTHONPATH': str(a.toolkit)})
