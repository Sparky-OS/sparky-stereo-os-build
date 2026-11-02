#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Exercise each recipe's Debian-directory staging statement with contaminated inputs."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--baseline-ref', required=True)
parser.add_argument('--repository', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
packages = ('dmemcg-booster', 'kcgroups', 'plasma-foreground-booster',
            'nvidia-kernel-open-dkms-stereo3d')
notes = ('private-note', 'bin/__pycache__/stray.pyc', 'test/__pycache__/stray.pyc', 'lib/stray.pyc')


def inventory(root):
    return {str(p.relative_to(root)): (p.lstat().st_mode & 0o7777,
            os.readlink(p) if p.is_symlink() else p.read_bytes())
            for p in root.rglob('*') if p.is_file() or p.is_symlink()}


for package in packages:
    relative = 'sparky-os/packages/' + package
    tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--',
                                      relative + '/debian']).decode().split('\0')
    for case in ('red', 'green', 'export'):
        root = args.work.resolve() / package / case
        recipe = root / relative
        for name in filter(None, tracked):
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / name, target, follow_symlinks=False)
        expected = inventory(recipe / 'debian')
        if case != 'export':
            subprocess.run(['git', '-C', str(root), 'init', '-q'], check=True)
            subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
        for name in notes:
            target = recipe / 'debian' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('planted private test input\n')
        if case == 'red':
            script = subprocess.check_output(['git', '-C', str(repo), 'show',
                                              args.baseline_ref + ':' + relative + '/build.sh']).decode()
        else:
            script = (repo / relative / 'build.sh').read_text()
        # Run the production statement, not a copy of its implementation. No compiler or network is needed.
        statements = [line for line in script.splitlines()
                      if '"$HERE/debian"' in line and line.startswith(('cp ', 'python3 '))]
        assert len(statements) == 1, statements
        work = root / 'upstream'
        source_name = 'nvidia-kmod-open' if package.startswith('nvidia-') else package
        version = subprocess.check_output(['dpkg-parsechangelog', '-l', str(recipe / 'debian/changelog'),
                                           '-S', 'Version'], text=True).strip()
        upstream = version.rsplit('-', 1)[0]
        original, = args.repository.rglob(source_name + '_' + upstream + '.orig.tar.xz')
        work.mkdir(parents=True)
        (work / original.name).symlink_to(original.resolve())
        subprocess.run(['tar', '-xJf', str(original), '-C', str(work)], check=True)
        source = work / (source_name + '-' + upstream)
        before_upstream = inventory(source)
        subprocess.run(['bash', '-euc', statements[0]], check=True,
                       env=os.environ | {'HERE': str(recipe), 'WORK': str(work), 'UPV': upstream,
                                         'COPY_RECIPE': str(repo / 'tools/copy-recipe.py')})
        actual = inventory(source / 'debian')
        assert {k: v for k, v in inventory(source).items() if not k.startswith('debian/')} == before_upstream
        if case == 'red':
            assert all(name in actual for name in notes)
            assert {k: v for k, v in actual.items() if k not in notes} == expected
        else:
            if case == 'export':
                expected['private-note'] = (0o644, b'planted private test input\n')
            assert actual == expected, (package, case, actual.keys() ^ expected.keys())
        with (root / 'dpkg-source.log').open('w') as log:
            subprocess.run(['dpkg-source', '-b', str(source)], cwd=work, check=True,
                           stdout=log, stderr=subprocess.STDOUT)
        with tarfile.open(work / (source_name + '_' + version + '.debian.tar.xz')) as tar:
            archived = {m.name: (m.mode, m.linkname if m.issym() else tar.extractfile(m).read())
                        for m in tar if m.isfile() or m.issym()}
        assert archived == {'debian/' + k: v for k, v in actual.items()}, (package, case)
        print(package, case, 'PASS', len(actual), 'files; source archive bytes, modes and links checked', flush=True)
        shutil.rmtree(source)
