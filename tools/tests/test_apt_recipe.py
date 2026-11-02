#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Exercise a milestone-one recipe with checkout contamination and without Git."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--repository', type=Path, required=True)
parser.add_argument('--baseline-ref', required=True)
parser.add_argument('--package', choices=('sparky-stereo-apt', 'sparky-stereo-hardware'), default='sparky-stereo-apt')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
paths = ['sparky-os/packages/' + args.package, 'sparky-os/apt', 'sparky-os/lean',
         'sparky-os/repo/provenance.sh', 'sparky-os/packages/dpkg-stereo/LICENSE', 'tools/copy-recipe.py']
tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--', *paths]).split(b'\0')
results = {}
for case in ('red', 'green', 'export'):
    root = work / case
    root.mkdir()
    for entry in tracked:
        if not entry:
            continue
        name = os.fsdecode(entry)
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / name, target)
    recipe = root / paths[0]
    if case == 'red':
        (recipe / 'build.sh').write_bytes(subprocess.check_output([
            'git', '-C', str(repo), 'show', args.baseline_ref + ':' + paths[0] + '/build.sh']))
    if case != 'export':
        subprocess.run(['git', '-C', str(root), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
    inputs = [(recipe, '')]
    if args.package == 'sparky-stereo-apt':
        inputs.append((root / 'sparky-os/apt', 'apt-generator/'))
    for folder, _ in inputs:
        for name in ('bin/__pycache__/a.pyc', 'test/__pycache__/b.pyc', 'lib/stray.pyc', 'untracked-note'):
            p = folder / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('planted test input\n')
    if args.package == 'sparky-stereo-hardware':
        for name in ('lib/stray.txt', 'lang/stray.txt'):
            (recipe / name).write_text('planted test input\n')
    out = work / (case + '-out')
    env = os.environ | {'OUT': str(out), 'SPARKY_SCRATCH': str(work), 'REPO': str(args.repository.resolve()),
                        'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com',
                        'PYTHONDONTWRITEBYTECODE': '1'}
    with (work / (case + '.log')).open('w') as log:
        subprocess.run(['bash', str(recipe / 'build.sh')], env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
    archive, = out.glob('*.tar.xz')
    with tarfile.open(archive) as tar:
        members = {m.name.split('/authoring/', 1)[1]: m for m in tar.getmembers()
                   if '/authoring/' in m.name and not m.isdir()}
        cache_names = [n for n in members if '__pycache__' in Path(n).parts or n.endswith('.pyc')]
        assert not cache_names, cache_names
        notes = {prefix + 'untracked-note' for _, prefix in inputs}
        if args.package == 'sparky-stereo-hardware':
            notes.update(('lib/stray.txt', 'lang/stray.txt'))
        if case in ('red', 'export'):
            assert notes <= members.keys(), members.keys()
        else:
            expected = set()
            for source, prefix in inputs:
                for entry in subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z', '--', '.']).split(b'\0'):
                    if entry:
                        name = os.fsdecode(entry)
                        expected.add(prefix + name)
                        assert tar.extractfile(members[prefix + name]).read() == (source / name).read_bytes(), name
            expected.add('build-tools/copy-recipe.py')
            assert members.keys() == expected, (members.keys() - expected, expected - members.keys())
            assert tar.extractfile(members['build-tools/copy-recipe.py']).read() == (repo / 'tools/copy-recipe.py').read_bytes()
    if args.package == 'sparky-stereo-hardware':
        deb = next(out.glob('sparky-stereo-hardware_*_all.deb'))
        payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(deb)])
        with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
            stray = [n for n in tar.getnames() if n.endswith('/stray.txt')]
        assert len(stray) == (0 if case == 'green' else 2), stray
    results[case] = {'archive': str(archive), 'authoring_files': len(members),
                     'notes_present': sorted(notes & members.keys()), 'caches': cache_names,
                     'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}
    print(case, results[case], flush=True)
(work / 'recipe-results.json').write_text(json.dumps(results, indent=2) + '\n')
