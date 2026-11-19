#!/usr/bin/python3
# Copyright 2026 Daniel Campos Ramos, GPL-3.0-or-later.
"""Repackage this icon-only revision from pinned, qualified predecessor archives.

Cold builds keep the ordinary native build. This path never invokes a compiler:
it restores authored payload text through its HR companion, checks unchanged
native source and runtime controls, and runs the normal payload and link gates.
"""
import gzip
import hashlib
import json
import lzma
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'sparky-lean-toolkit'))
from lean import buildrecord, debhelper, package, release

root = Path.cwd()
archives = Path(sys.argv[1]).resolve()
out = root.parent
plan = json.loads((root / 'debian/repack-predecessor.json').read_text())
work = out / 'icon-repack'
work.mkdir()
sha = lambda p: hashlib.file_digest(p.open('rb'), 'sha256').hexdigest()

for name, expected in plan['archives'].items():
    if sha(archives / name) != expected:
        raise SystemExit('Predecessor archive hash mismatch: ' + name)
parent_record = json.loads((archives / plan['build_record']['name']).read_text())
assert sha(archives / plan['build_record']['name']) == plan['build_record']['sha256']
assert parent_record['recipeCommit'] == plan['compiled_recipe_commit']
assert not parent_record['unrecorded']
assert sha(archives / plan['source']['name']) == plan['source']['sha256']
previous = work / 'previous-source'
subprocess.run(['dpkg-source', '-x', str(archives / plan['source']['name']), str(previous)], check=True)
assert json.loads((root / 'debian/build-origin.json').read_text())['fork'] == plan['fork_commit']
assert (root / 'debian/build-origin.json').read_bytes() == (previous / 'debian/build-origin.json').read_bytes()

def source_files(folder, debian=False):
    result = {}
    for p in sorted(folder.rglob('*')):
        rel = p.relative_to(folder)
        if '.pc' in rel.parts or '.sparky-lc' in rel.parts:
            continue
        if not debian and rel.parts[0] == 'debian':
            continue
        if p.is_symlink():
            result[str(rel)] = ['link', str(p.readlink())]
        elif p.is_file():
            result[str(rel)] = [p.stat().st_mode & 0o777, sha(p)]
    return result

assert source_files(root) == source_files(previous), 'Native source/components changed: compile normally'
allowed = {'rules', 'changelog', 'control', 'install-icons.py', 'repack-icons.py', 'repack-predecessor.json', 'README.Debian', 'generate.py'}
before = source_files(previous / 'debian', True)
after = source_files(root / 'debian', True)
assert {k: v for k, v in before.items() if k not in allowed} == {k: v for k, v in after.items() if k not in allowed}
assert (root / 'debian/generate.py').read_text() == (previous / 'debian/generate.py').read_text().replace(plan['previous_version'], plan['version'])
# No runtime dependency or profile change may be silently carried past this path.
assert (root / 'debian/control').read_text().split('\n\n', 1)[1] == (previous / 'debian/control').read_text().split('\n\n', 1)[1]

hr = work / 'previous-hr'
hr.mkdir()
for name in plan['archives']:
    if '-lc-hr_' in name:
        subprocess.run(['dpkg-deb', '-x', str(archives / name), str(hr)], check=True)

buildrecord.note_start(out)
built = []
binary_hashes = {}
restored = []
(root / 'debian/files').unlink(missing_ok=True)
for name in plan['archives']:
    if '-lc-hr_' in name:
        continue
    staging = work / name.split('_')[0]
    subprocess.run(['dpkg-deb', '-R', str(archives / name), str(staging)], check=True)
    fields = package.control(staging)
    p, v, arch = package.identity(fields)
    assert v == plan['previous_version']
    manifest_path = staging / package.manifest_path(p, arch).lstrip('/')
    manifest = package.load(fields[package.FIELD.lower()], manifest_path.read_bytes(), p, v, arch)
    package.check_tree(staging)
    for row in manifest['files']:
        if row.get('status') == 'projected':
            authored = lzma.decompress((hr / package.hr_path(p, arch, row['sha_hr']).lstrip('/')).read_bytes())
            assert hashlib.sha256(authored).hexdigest() == row['sha_hr']
            target = staging / row['path'].lstrip('/')
            target.write_bytes(authored)
            restored.append([p, row['path'], row['sha_hr']])
    manifest_path.unlink()
    control = staging / 'DEBIAN/control'
    text = control.read_text().replace(plan['previous_version'], plan['version'])
    text = re.sub(r'(?m)^Sparky-Lean-Code:.*\n', '', text)
    text = re.sub(r'(?m)^Breaks: dpkg-stereo \(<< 0\.1\.6\)\n', '', text)
    control.write_text(text)
    changelog = staging / f'usr/share/doc/{p}/changelog.Debian.gz'
    if changelog.is_file() and not changelog.is_symlink():
        changelog.write_bytes(gzip.compress((root / 'debian/changelog').read_bytes(), mtime=0))
    if p == 'spirula-studio':
        assert (staging / 'usr/bin/spirula-studio').read_bytes() == (root / 'debian/launch.py').read_bytes()
        assert (staging / 'usr/share/applications/spirula-studio.desktop').read_bytes() == (root / 'debian/spirula-studio.desktop').read_bytes()
        subprocess.run([sys.executable, 'debian/install-icons.py', 'assets/icon.png', str(staging / 'usr/share/icons/hicolor')], check=True)
        for declaration in staging.glob('usr/share/sparky-install-models/profiles/*.json'):
            data = json.loads(declaration.read_text())
            assert data['version'] == plan['previous_version']
            data['version'] = plan['version']
            declaration.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    for executable in staging.glob('usr/lib/spirula-studio/*/spirula'):
        binary_hashes[str(executable.relative_to(staging))] = sha(executable)
    subprocess.run(['bash', 'debian/sparky-lean-toolkit/provenance.sh', '--tree', str(staging), '--source', str(root)], check=True)
    old_outputs = set(out.glob('*.deb'))
    release.build_tree(staging, out)
    outputs = sorted(set(out.glob('*.deb')) - old_outputs)
    built.extend(outputs)
    for output in outputs:
        automatic = '-lc-hr_' in output.name or '-dbgsym_' in output.name
        subprocess.run(['dpkg-distaddfile', output.name, 'doc' if '-lc-hr_' in output.name else fields.get('section', 'graphics'), fields.get('priority', 'optional')], check=True)
        if automatic:
            files = root / 'debian/files'
            files.write_text(''.join(line + (' automatic=yes' if line.split()[0] == output.name else '') + '\n' for line in files.read_text().splitlines()))
    for executable in staging.glob('usr/lib/spirula-studio/*/spirula'):
        assert sha(executable) == binary_hashes[str(executable.relative_to(staging))]

assert len(built) == 39
debhelper.link_gate(built)
release.check_debs([str(p) for p in built])
(out / 'icon-repack-evidence.json').write_text(json.dumps({'no_native_compilation': True, 'native_source_and_components_unchanged': True, 'runtime_control_paragraphs_unchanged': True, 'predecessor_build_record': plan['build_record'], 'predecessor_archives': plan['archives'], 'authored_files_restored_from_hr': restored, 'executable_sha256': binary_hashes, 'qualified_archives': len(built)}, indent=2) + '\n')
