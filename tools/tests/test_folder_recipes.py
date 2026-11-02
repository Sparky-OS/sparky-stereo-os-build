#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Build contaminated baseline, tracked-only and export recipe fixtures."""
import argparse
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

RECIPES = {
    'sparky-stereo-align': None,
    'sparky-stereo-mkv-mark': None,
    'sparky-stereo-integration': 'lang',
    'calamares-settings-sparky-stereo': 'lib/lang',
    'sparky-stereo-calamares-branding': 'usr/share',
    'xpadneo-dkms': 'upstream/src',
}


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def prove(repo, work, package, baseline):
    recipe_path = 'sparky-os/packages/' + package
    inputs = [recipe_path, 'sparky-os/lean', 'sparky-os/repo/provenance.sh',
              'sparky-os/packages/dpkg-stereo/LICENSE', 'tools/copy-recipe.py',
              'sparky-os/packages/sparky-stereo-integration/make-pack.py']
    tracked = [os.fsdecode(n) for n in run('git', '-C', str(repo), 'ls-files', '-z', '--', *inputs).split(b'\0') if n]
    results = {}
    for case in ('red', 'green', 'export'):
        root = work / case
        root.mkdir(parents=True)
        for name in tracked:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / name, target, follow_symlinks=False)
        recipe = root / recipe_path
        if case == 'red':
            (recipe / 'build.sh').write_bytes(run('git', '-C', str(repo), 'show', baseline + ':' + recipe_path + '/build.sh'))
        if case != 'export':
            run('git', '-C', str(root), 'init', '-q')
            run('git', '-C', str(root), 'add', '.')
        notes = {'untracked-recipe-note'}
        if RECIPES[package]:
            notes.add(RECIPES[package] + '/untracked-payload-note')
        for name in (*notes, 'bin/__pycache__/stray.pyc', 'test/__pycache__/stray.pyc', 'lib/stray.pyc'):
            target = recipe / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('planted test data\n')
        output = work / (case + '-out')
        env = os.environ | {'OUT': str(output), 'TMPDIR': str(work), 'SPARKY_SCRATCH': str(work),
                            'PYTHONDONTWRITEBYTECODE': '1', 'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
                            'DEBEMAIL': 'Capitain_Jack@yahoo.com'}
        with (work / (case + '.log')).open('w') as log:
            subprocess.run(['bash', str(recipe / 'build.sh')], env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
        archive, = output.glob('*.tar.xz')
        with tarfile.open(archive) as tar:
            members = {m.name.split('/authoring/', 1)[1]: m for m in tar.getmembers()
                       if '/authoring/' in m.name and not m.isdir()}
            assert not [n for n in members if '__pycache__' in Path(n).parts or n.endswith('.pyc')]
            if case == 'green':
                expected = {os.fsdecode(n) for n in run('git', '-C', str(recipe), 'ls-files', '-z', '--', '.').split(b'\0') if n}
                for name in expected:
                    path, member = recipe / name, members[name]
                    if path.is_symlink():
                        assert member.issym() and member.linkname == os.readlink(path), name
                    else:
                        assert tar.extractfile(member).read() == path.read_bytes(), name
                expected.add('build-tools/copy-recipe.py')
                if package in ('sparky-stereo-align', 'sparky-stereo-mkv-mark'):
                    expected.add('make-pack.py')
                assert members.keys() == expected, (members.keys() - expected, expected - members.keys())
            else:
                assert notes <= members.keys(), notes - members.keys()
        payload_notes = []
        for deb in output.glob('*.deb'):
            with tarfile.open(fileobj=io.BytesIO(run('dpkg-deb', '--fsys-tarfile', str(deb)))) as tar:
                payload_notes.extend(n for n in tar.getnames() if n.endswith('/untracked-payload-note'))
        if RECIPES[package]:
            assert bool(payload_notes) == (case != 'green'), payload_notes
        results[case] = {'archive': str(archive), 'authoring_files': len(members),
                         'source_notes': sorted(notes & members.keys()), 'payload_notes': payload_notes}
        print(package, case, results[case], flush=True)
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--package', choices=RECIPES, required=True)
    parser.add_argument('--baseline-ref', required=True)
    args = parser.parse_args()
    prove(Path(__file__).resolve().parents[2], args.work.resolve(), args.package, args.baseline_ref)
