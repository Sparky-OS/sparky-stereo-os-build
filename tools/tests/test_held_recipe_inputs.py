#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Contaminate the five held recipes and inspect their real source archives."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

PACKAGES = ('sparky-stereo-cushion-swap', 'sparky-stereo-graphics',
            'sparky-stereo-grub-l10n', 'sparky-stereo-memory-kcm', 'dpkg-stereo')
NATIVE = (PACKAGES[0], PACKAGES[1], PACKAGES[3])
NOTES = ('untracked-note', 'bin/__pycache__/stray.pyc',
         'test/__pycache__/stray.pyc', 'lib/stray.pyc')


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def inventory(root):
    return {str(p.relative_to(root)): (p.lstat().st_mode & 0o777,
            os.readlink(p) if p.is_symlink() else p.read_bytes())
            for p in root.rglob('*') if p.is_file() or p.is_symlink()}


def prove(repo, work, package, baseline):
    relative = 'sparky-os/packages/' + package
    inputs = (relative, 'sparky-os/lean', 'tools/copy-recipe.py',
              'sparky-os/repo/provenance.sh', 'sparky-os/packages/dpkg-stereo/LICENSE')
    tracked = run('git', '-C', str(repo), 'ls-files', '-z', '--', *inputs).decode().split('\0')
    results = {}
    for case in ('red', 'green', 'export'):
        root = work / case
        for name in filter(None, tracked):
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / name, target, follow_symlinks=False)
        recipe = root / relative
        if case == 'red':
            for script in ('build.sh', 'build-source.sh') if package == 'dpkg-stereo' else ('build.sh',):
                (recipe / script).write_bytes(run('git', '-C', str(repo), 'show', baseline + ':' + relative + '/' + script))
        expected = inventory(recipe)
        if case != 'export':
            run('git', '-C', str(root), 'init', '-q')
            run('git', '-C', str(root), 'add', '.')
        for name in NOTES:
            p = recipe / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('# planted private input\n')
        # The old dpkg recipe already filters its own folder; its engine wildcard does not.
        engine_note = root / 'sparky-os/lean/untracked_engine_note.py'
        engine_note.write_text('# planted private engine note\n')
        output = work / (case + '-out')
        output.mkdir()
        env = os.environ | {'OUT': str(output), 'TMPDIR': str(work),
                            'PYTHONDONTWRITEBYTECODE': '1',
                            'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
                            'DEBEMAIL': 'Capitain_Jack@yahoo.com'}
        with (work / (case + '.log')).open('w') as log:
            if package in NATIVE:
                script = (recipe / 'build.sh').read_text()
                # Execute the complete production source-packaging tail, including dpkg-source.
                # Compilation is exercised independently by the real recipe and native rebuild.
                tail = script[script.index('S=$WORK/$PACKAGE-$VERSION'):]
                tail = tail.split('\n"$TOOLKIT/repo/provenance.sh"')[0]
                tail = tail.split('\n"$HERE/../../repo/provenance.sh"')[0]
                version = next(l.split('=', 1)[1] for l in script.splitlines() if l.startswith('VERSION='))
                (output / 'source-work').mkdir()
                env |= {'HERE': str(recipe), 'WORK': str(output / 'source-work'), 'PACKAGE': package,
                        'VERSION': version, 'DEPENDS': 'libc6'}
                subprocess.run(['bash', '-euc', tail], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            else:
                builder = 'build-source.sh' if package == 'dpkg-stereo' else 'build.sh'
                subprocess.run(['bash', str(recipe / builder)], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        archive, = output.glob('*.tar.xz')
        with tarfile.open(archive) as tar:
            members = {m.name.split('/', 1)[1]: m for m in tar if '/' in m.name and not m.isdir()}
            prefix = relative + '/' if package == 'dpkg-stereo' else ('authoring/' if package == PACKAGES[2] else '')
            actual = {n.removeprefix(prefix): (m.mode, m.linkname if m.issym() else tar.extractfile(m).read())
                      for n, m in members.items() if n.startswith(prefix)}
            if package in NATIVE:
                actual = {n: v for n, v in actual.items() if not n.startswith('debian/')}
            elif package == PACKAGES[2]:
                actual = {n: v for n, v in actual.items() if not n.startswith('upstream-po/') and n != 'COPYING.grub'}
            if case == 'green':
                if package != 'dpkg-stereo':
                    expected['build-tools/copy-recipe.py'] = (0o644, (repo / 'tools/copy-recipe.py').read_bytes())
                assert actual == expected, (package, actual.keys() ^ expected.keys(), [n for n in expected.keys() & actual.keys() if expected[n] != actual[n]])
                assert 'sparky-os/lean/untracked_engine_note.py' not in members
            elif case == 'export':
                assert 'untracked-note' in actual
            elif package != 'dpkg-stereo':
                assert (set(NOTES) if package in NATIVE else {'untracked-note'}) <= actual.keys(), actual.keys()
            else:
                assert 'sparky-os/lean/untracked_engine_note.py' in members
            if case != 'red':
                assert not [n for n in members if '__pycache__' in Path(n).parts or n.endswith('.pyc')]
            results[case] = {'archive': str(archive), 'recipe_files': len(actual),
                             'planted_recipe_paths': sorted(set(NOTES) & actual.keys()),
                             'engine_note_ships': 'sparky-os/lean/untracked_engine_note.py' in members}
        print(package, case, results[case], flush=True)
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--package', choices=PACKAGES, required=True)
    parser.add_argument('--baseline-ref', required=True)
    args = parser.parse_args()
    args.work.mkdir(parents=True)
    prove(Path(__file__).resolve().parents[2], args.work.resolve(), args.package, args.baseline_ref)
