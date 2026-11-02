#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Check the CEC, skills and meta builders' custom source archive layouts."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--kind', choices=('cec', 'skills', 'meta'), required=True)
parser.add_argument('--inputs', type=Path, required=True)
parser.add_argument('--repository', type=Path, required=True)
parser.add_argument('--baseline-ref', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
work = args.work.resolve()
package = 'sparky-stereo-' + args.kind
recipe_relative = 'sparky-os/packages/' + package
inputs = [recipe_relative, 'sparky-os/lean', 'sparky-os/repo/provenance.sh',
          'sparky-os/lists', 'sparky-os/packages/dpkg-stereo/LICENSE', 'tools/copy-recipe.py']
tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--', *inputs]).split(b'\0')
results = {}
baseline_files = None
for case in ('red', 'green', 'export'):
    root = work / case
    root.mkdir(parents=True)
    for entry in tracked:
        if not entry:
            continue
        name = os.fsdecode(entry)
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / name, target, follow_symlinks=False)
    recipe = root / recipe_relative
    if args.kind == 'skills':
        public, = args.inputs.glob('sparky-stereo-skills/*/public')
        shutil.copytree(public, recipe / 'public', symlinks=True)
    if case == 'red':
        changed = 'build-source.py' if args.kind == 'meta' else 'build.sh'
        (recipe / changed).write_bytes(subprocess.check_output([
            'git', '-C', str(repo), 'show', args.baseline_ref + ':' + recipe_relative + '/' + changed]))
    if case != 'export':
        subprocess.run(['git', '-C', str(root), 'init', '-q'], check=True)
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
    source = root / 'sparky-os/lists' if args.kind == 'meta' else recipe
    for name in ('untracked-recipe-note', 'bin/__pycache__/stray.pyc', 'test/__pycache__/stray.pyc', 'lib/stray.pyc'):
        target = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('planted test data\n')
    if args.kind == 'skills':
        (source / 'lang/untracked-recipe-note').write_text('planted payload data\n')
    output = work / (case + '-out')
    env = os.environ | {'OUT': str(output), 'TMPDIR': str(work), 'SPARKY_SCRATCH': str(work),
                        'REPO': str(args.repository.resolve()), 'PYTHONDONTWRITEBYTECODE': '1',
                        'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com'}
    if args.kind == 'meta':
        env |= {'PACKAGES': 'sparky-stereo-integrations', 'VERSION': '20261102'}
    with (work / (case + '.log')).open('w') as log:
        subprocess.run(['bash', str(recipe / 'build.sh')], env=env, check=True, stdout=log, stderr=subprocess.STDOUT)
    if args.kind == 'skills':
        binary, = output.glob('sparky-stereo-skills_*_all.deb')
        payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(binary)])
        import io
        with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
            leaked = any(m.name.endswith('/untracked-recipe-note') for m in tar.getmembers())
        assert leaked == (case != 'green'), (case, leaked)
    archive, = output.glob('*.tar.xz')
    with tarfile.open(archive) as tar:
        members = {m.name.split('/', 1)[1]: m for m in tar.getmembers() if '/' in m.name and not m.isdir()}
        notes = [n for n in members if n.endswith('/untracked-recipe-note') or n == 'untracked-recipe-note']
        caches = [n for n in members if '__pycache__' in Path(n).parts or n.endswith('.pyc')]
        if case == 'red':
            assert notes, members.keys()
            baseline_files = members.keys() - set(notes) - set(caches)
        else:
            assert not caches, caches
            if case == 'green':
                assert not notes, notes
            else:
                assert notes, members.keys()
            helper = ('generator-inputs/' if args.kind == 'meta' else '') + 'build-tools/copy-recipe.py'
            expected = baseline_files | {helper} | set(notes)
            assert members.keys() == expected, (members.keys() - expected, expected - members.keys())
            assert tar.extractfile(members[helper]).read() == (repo / 'tools/copy-recipe.py').read_bytes()
            # Compare the actual indexed inputs, allowing only generated Debian packaging.
            if case == 'green':
                prefix = 'generator-inputs/lists/' if args.kind == 'meta' else ''
                names = subprocess.check_output(['git', '-C', str(source), 'ls-files', '-z', '--', '.']).split(b'\0')
                for entry in names:
                    if not entry:
                        continue
                    name = os.fsdecode(entry)
                    if args.kind != 'meta' and name.startswith('debian/'):
                        continue
                    member, path = members[prefix + name], source / name
                    if path.is_symlink():
                        assert member.issym() and member.linkname == os.readlink(path), name
                    else:
                        assert tar.extractfile(member).read() == path.read_bytes(), name
    results[case] = {'archive': str(archive), 'files': len(members), 'notes': notes, 'caches': caches}
    print(package, case, results[case], flush=True)
(work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
