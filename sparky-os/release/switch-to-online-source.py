#!/usr/bin/env python3
"""Install reviewed edition APT payload after online verification; keep other sources/pins."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('bootstrap', type=Path)
p.add_argument('report', type=Path)
p.add_argument('--hostname', required=True)
p.add_argument('--verification', type=Path, required=True)
args = p.parse_args()
assert os.geteuid() == 0 and socket.gethostname() == args.hostname
assert not args.report.exists()
verification = json.loads(args.verification.read_text())
assert verification['state'] == 'passed'
assert verification['inrelease_sha256'] == '2c5a3d5cb98727a7242d7b42b74567b6ec255d1af94e3a1fef174b9636a59cce'
allowed = {
    'etc/apt/trusted.gpg.d/sparky-stereo-repo.asc',
    'etc/apt/sources.list.d/sparky-stereo.sources',
    'etc/apt/preferences.d/sparky-stereo',
    'etc/apt/preferences.d/sparky-stereo-only-ours',
}
rows = json.loads((args.bootstrap / 'manifest.json').read_text())
assert {row['path'] for row in rows} == allowed and len(rows) == len(allowed)
for row in rows:
    source = args.bootstrap / 'payload' / row['path']
    assert source.is_file() and not source.is_symlink()
    assert hashlib.sha256(source.read_bytes()).hexdigest() == row['sha256']
key = args.bootstrap / 'payload/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc'
keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--show-keys', str(key)], text=True)
assert next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:')) == '10DFD38DAD1E4808BC688E5A945E5D079A2A0B9C'
old = Path('/etc/apt/sources.list.d/sparky-stereo-local.list')
assert old.is_file() and not old.is_symlink()
assert ('file:' + str(cfg.path('SPARKY_REPO_DIR')) if args.hostname == cfg.get('SPARKY_WORKSTATION_HOSTNAME')
        else 'file:/var/local/sparky-stereo-repo') in old.read_text()
args.report.parent.mkdir(parents=True, exist_ok=True)
backup = args.report.parent / 'online-source-replaced'
assert not backup.exists()
backup.mkdir(mode=0o700)
for row in rows:
    target = Path('/') / row['path']
    assert not target.is_symlink()
    if target.exists():
        destination = backup / row['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, destination)
shutil.copy2(old, backup / old.name)
for row in rows:
    target = Path('/') / row['path']
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as stream:
        stream.write((args.bootstrap / 'payload' / row['path']).read_bytes())
        name = stream.name
    os.chmod(name, 0o644)
    os.replace(name, target)
old.unlink()
args.report.write_text(json.dumps(dict(state='configured', hostname=args.hostname,
    timestamp_utc=datetime.now(timezone.utc).isoformat(), files=rows,
    verified_inrelease=verification['inrelease_sha256'],
    scope='Only edition source, public key and two edition pins; other update roots preserved'), indent=2) + '\n')
print('Configured signed online edition source on', args.hostname)
