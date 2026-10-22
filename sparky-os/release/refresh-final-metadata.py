#!/usr/bin/env python3
"""Build final metas and APT configuration after all native candidates exist.

Uses a private copy of the generators so generating APT pins never dirties the
public checkout. Retains superseded candidate artifacts; no publication/install.
"""
import hashlib
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
kit = (cfg.TREE / 'sparky-os')
original = cfg.path('SPARKY_REPO_DIR')
sys.path.insert(0, str(kit))
from lean.package import stanzas

subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/checkpoint.py'))], check=True)
progress = json.loads((notes / 'migration-progress.json').read_text())
assert not progress['failed_native_jobs'], 'Complete native builds before final metadata'
for name in ['mesa', 'wine', 'abseil']:
    for arch in ['amd64', 'i386']:
        status = json.loads((base / 'jobs' / (name + '-' + arch) / 'status.json').read_text())
        assert status['state'] == 'candidate-needs-review' and status['exit_code'] == 0
for flavour in ['base', 'v3', 'rt']:
    path = base / 'jobs' / ('linux-stereo-' + flavour + '-amd64') / 'status.json'
    status = json.loads(path.read_text())
    assert status['state'] == 'candidate-needs-review' and status['exit_code'] == 0

out = base / 'final-metadata'
out.mkdir()
working = out / 'toolkit'
for relative in ['lean', 'lists', 'apt', 'packages/sparky-stereo-meta',
                 'packages/sparky-stereo-apt']:
    shutil.copytree(kit / relative, working / relative,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '.git'))
(working / 'repo').mkdir()
shutil.copy2(kit / 'repo/provenance.sh', working / 'repo/provenance.sh')
(working / 'packages/dpkg-stereo').mkdir()
shutil.copy2(kit / 'packages/dpkg-stereo/LICENSE', working / 'packages/dpkg-stereo/LICENSE')
inventory = {str(p.relative_to(working)): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in working.rglob('*') if p.is_file()}
(out / 'generator-inputs.json').write_text(json.dumps(inventory, indent=2) + '\n')

initial = json.loads((notes / 'current-packages.json').read_text())
archives = {Path(r['archive']) for r in progress['archives']}
archives.update(original / r['Filename'] for r in initial
                if r.get('Sparky-Lean-Code', '').startswith('lc1 '))
controls = {}
for archive in sorted(archives):
    text = subprocess.check_output(['dpkg-deb', '-f', str(archive)], text=True).rstrip()
    row = next(stanzas(text))
    key = row['package'], row['architecture']
    old = controls.get(key)
    if old and subprocess.run(['dpkg', '--compare-versions', row['version'], 'le', old[0]]).returncode == 0:
        continue
    controls[key] = row['version'], text, archive
index = out / 'index'
index.mkdir()
with (index / 'Packages').open('w') as stream:
    for version, control, archive in controls.values():
        stream.write(control + '\nFilename: ./pool/' + archive.name + '\n\n')

meta = base / 'meta'
retired = meta / 'attempt-20261020'
retired.mkdir()
for archive in list(meta.glob('*.deb')):
    source = subprocess.check_output(['dpkg-deb', '-f', str(archive), 'Source'], text=True).split()[0]
    if source == 'sparky-stereo-meta':
        shutil.move(archive, retired / archive.name)
for path in list(meta.glob('sparky-stereo-meta_*')):
    assert path.is_file()
    shutil.move(path, retired / path.name)
repeat = base / 'source-rebuilds/sparky-stereo-meta'
if repeat.exists():
    retired_repeat = repeat.with_name('sparky-stereo-meta-attempt-20261020')
    assert not retired_repeat.exists()
    shutil.move(repeat, retired_repeat)
env = dict(os.environ, REPO=str(index), OUT=str(meta), BUILD_ROOT=str(out),
           TMPDIR=str(out), VERSION=datetime.now().strftime('%Y%m%d') + '.1',
           KERNEL_META_VERSION_SUFFIX='+lc1')
subprocess.run(['bash', str(working / 'packages/sparky-stereo-meta/build.sh')], env=env, check=True)
subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/check-source-rebuild.py')), 'meta:sparky-stereo-meta'], check=True)

apt = base / 'scripts/sparky-stereo-apt'
apt.mkdir()
env.update(OUT=str(apt), VERSION='20261008.1~sparky9~0+lc1', DEB_SRC='1')
subprocess.run(['bash', str(working / 'packages/sparky-stereo-apt/build.sh')], env=env, check=True)
subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/check-source-rebuild.py')), 'scripts:sparky-stereo-apt'], check=True)
subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/checkpoint.py'))], check=True)
subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/audit-candidate-sources.py'))], check=True)
(out / 'status.json').write_text(json.dumps(dict(state='candidate-needs-review',
    scope='Final metadata candidate; complete repository/dependency checks still required'), indent=2) + '\n')
print('Final metadata candidates and retained-source comparisons completed')
