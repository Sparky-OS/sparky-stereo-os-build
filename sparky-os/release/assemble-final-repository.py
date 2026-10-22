#!/usr/bin/env python3
"""Assemble the qualified signed local tree without another archive-sized copy.

Requires stage-final-repository.py --stage to have completed. This creates only
a local candidate, never uploads it or changes the workstation's APT sources.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

base = cfg.path('SPARKY_MIGRATION_WORK')
source = base / 'final-repository-inputs'
selection = json.loads((source / 'selection.json').read_text())
assert not selection['missing_original_identities'] and not selection['qualification_gaps']
destination = base / 'final-repository'
destination.mkdir()

def link(path, name, expected):
    assert path.is_file() and not path.is_symlink()
    with path.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').hexdigest() == expected
    prefix = name[:4] if name.startswith('lib') and len(name) > 3 else name[0]
    target = destination / 'pool/main' / prefix / name / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    assert target.parent.stat().st_dev == path.stat().st_dev
    if target.exists():
        assert os.path.samefile(path, target)
    else:
        try:
            target.hardlink_to(path)
        except PermissionError:
            subprocess.run(['sudo', '-n', 'ln', '--', str(path), str(target)], check=True)

for row in selection['binaries']:
    link(source / Path(row['archive']).name, row['source'], row['sha256'])
for row in selection['sources']:
    for item in row['files']:
        link(source / 'source' / Path(item['path']).name, row['source'], item['sha256'])
env = dict(os.environ, SPARKY_REPO_KEY='10DFD38DAD1E4808BC688E5A945E5D079A2A0B9C',
           SPARKY_REPO_GNUPGHOME=cfg.get('SPARKY_REPO_GNUPG'),
           TMPDIR=str(base))
with (base / 'logs/final-repository-assembly.log').open('w') as log:
    subprocess.run(['bash', str(cfg.TREE / 'sparky-os/repo/publish-tree.sh'),
                    str(source), str(destination)], env=env,
                   stdout=log, stderr=subprocess.STDOUT, check=True)
assert (destination / 'dists/mashtabba/main/source/Sources').is_file()
(base / 'final-repository-assembly.json').write_text(json.dumps(dict(
    state='assembled-needs-installed-and-online-checks', repository=str(destination),
    selection_sha256=hashlib.sha256((source / 'selection.json').read_bytes()).hexdigest(),
    inrelease_sha256=hashlib.sha256((destination / 'dists/mashtabba/InRelease').read_bytes()).hexdigest(),
    scope='Signed local candidate only; not published or installed'), indent=2) + '\n')
print('Signed local candidate assembled:', destination)
