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
    'sparky-stereo-look': 'default/desktoptheme/sparky-stereo-oxygen',
    'kubabbar-glass': 'share/themes',
    'kubabbar-glass-menubar': 'share/plasma/look-and-feel/kubabbar-glass-menubar',
}
EXTERNAL = {
    'sparky-backup-core-stereo': ('sparky-backup-core-stereo/9', 'SRC', 'upstream/', 'lib/untracked-payload-note'),
    'sparky-beep': ('sparky-beep', 'SRC', 'source/', 'lib/untracked-payload-note.sh'),
    'sparkyos-artwork': ('sparkyos-artwork/*/authoring/artwork', 'ART', 'artwork/', 'wallpapers/untracked-payload-note'),
    'sparkyos-plymouth': ('sparkyos-plymouth/*/authoring/artwork', 'ART', 'artwork/', 'sparkyos/untracked-payload-note'),
}
RECIPES.update({name: None for name in EXTERNAL})


def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)


def prove(repo, work, package, baseline, external_inputs=None):
    recipe_path = 'sparky-os/packages/' + ('kubabbar-glass' if package == 'kubabbar-glass-menubar' else package)
    builder = {'kubabbar-glass': 'tools/build_packages.sh', 'kubabbar-glass-menubar': 'tools/build_m3_package.sh'}.get(package, 'build.sh')
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
        source_inputs = [(recipe, 'builder/' if package == 'sparky-backup-core-stereo' else '')]
        external_env = {}
        if package in EXTERNAL:
            pattern, variable, prefix, payload_note = EXTERNAL[package]
            origin, = external_inputs.glob(pattern)
            external = root / 'external' / ('9' if package == 'sparky-backup-core-stereo' else 'source')
            subprocess.run(['python3', str(repo / 'tools/copy-recipe.py'), str(origin), str(external)], check=True)
            external_env[variable] = str(external.parent if package == 'sparky-backup-core-stereo' else external)
            source_inputs.append((external, prefix))
        if case == 'red':
            (recipe / builder).write_bytes(run('git', '-C', str(repo), 'show', baseline + ':' + recipe_path + '/' + builder))
        if case != 'export':
            run('git', '-C', str(root), 'init', '-q')
            run('git', '-C', str(root), 'add', '.')
        notes = set()
        for folder, prefix in source_inputs:
            if package == 'sparky-beep' and folder == recipe:
                continue
            notes.add(prefix + 'untracked-recipe-note')
            for name in ('untracked-recipe-note', 'bin/__pycache__/stray.pyc', 'test/__pycache__/stray.pyc', 'lib/stray.pyc'):
                target = folder / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('# planted test data\n')
        if RECIPES[package]:
            notes.add(RECIPES[package] + '/untracked-payload-note')
            target = recipe / RECIPES[package] / 'untracked-payload-note'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('planted test data\n')
        if package in EXTERNAL:
            notes.add(prefix + payload_note)
            (external / payload_note).write_text('# planted test data\n')
        output = work / (case + '-out')
        env = os.environ | {'OUT': str(output), 'DEST': str(output), 'TMPDIR': str(work), 'SPARKY_SCRATCH': str(work),
                            'PYTHONDONTWRITEBYTECODE': '1', 'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
                            'DEBEMAIL': 'Capitain_Jack@yahoo.com'} | external_env
        with (work / (case + '.log')).open('w') as log:
            subprocess.run(['bash', str(recipe / builder)], env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
        archives = sorted(output.glob('*.tar.xz'))
        assert archives, output
        for archive in archives:
            with tarfile.open(archive) as tar:
                members = {m.name.split('/authoring/', 1)[1]: m for m in tar.getmembers()
                           if '/authoring/' in m.name and not m.isdir()}
                assert not [n for n in members if '__pycache__' in Path(n).parts or n.endswith('.pyc')]
                if case == 'green':
                    expected = set()
                    for folder, prefix in source_inputs:
                        names = {os.fsdecode(n) for n in run('git', '-C', str(folder), 'ls-files', '-z', '--', '.').split(b'\0') if n}
                        if package == 'sparky-beep' and folder == recipe:
                            names = {'build.sh'}
                        for name in names:
                            expected.add(prefix + name)
                            path, member = folder / name, members[prefix + name]
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
                payload_notes.extend(n for n in tar.getnames() if '/untracked-payload-note' in n)
        if RECIPES[package] or package in EXTERNAL:
            assert bool(payload_notes) == (case != 'green'), payload_notes
        results[case] = {'archives': [str(a) for a in archives], 'authoring_files': len(members),
                         'source_notes': sorted(notes & members.keys()), 'payload_notes': payload_notes}
        print(package, case, results[case], flush=True)
    (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--package', choices=RECIPES, required=True)
    parser.add_argument('--baseline-ref', required=True)
    parser.add_argument('--inputs', type=Path, help='External source checkouts or published authoring exports')
    args = parser.parse_args()
    prove(Path(__file__).resolve().parents[2], args.work.resolve(), args.package, args.baseline_ref, args.inputs)
