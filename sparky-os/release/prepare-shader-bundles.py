#!/usr/bin/env python3
"""Prepare small, exact-original recovery bundles locally for the two upgrades."""
import hashlib
import json
import lzma
from pathlib import Path
import shutil
import tarfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
scratch = cfg.path('SPARKY_MIGRATION_WORK')
output = scratch / 'shader-recovery-bundles'
output.mkdir()
host = json.loads((scratch / 'shader-upgrade-proof/host-recovery-inputs-rechecked.json').read_text())
a10 = json.loads((notes / 'a10-uplift/shader-recovery-proof.json').read_text())
assert a10['passed'] and len(a10['files']) == 76 and len(host['files']) == 79
for machine, source in [('workstation', host), ('a10', a10)]:
    bundle = output / machine
    pristine = bundle / 'pristine'
    pristine.mkdir(parents=True)
    rows = []
    for row in source['files']:
        origin = Path(row['pristine']) if machine == 'workstation' else notes / row['cache']
        packed = origin.read_bytes()
        expected = row['sha256']
        assert hashlib.sha256(lzma.decompress(packed)).hexdigest() == expected
        (pristine / (expected + '.xz')).write_bytes(packed)
        rows.append(dict(path=row['path'], sha256=expected))
    shutil.copy2((cfg.TREE / 'sparky-os/release/seed-shader-recovery.py'), bundle / 'seed-shader-recovery.py')
    (bundle / 'manifest.json').write_text(json.dumps(dict(machine=machine, files=rows,
        scope='Exact old authored shader bytes; restoration remains owned by dpkg-stereo'), indent=2) + '\n')
    archive = output / (machine + '.tar.xz')
    with tarfile.open(archive, 'w:xz') as stream:
        stream.add(bundle, arcname=machine)
    print(machine, len(rows), 'files;', len(list(pristine.iterdir())), 'unique originals;',
          archive.stat().st_size, 'archive bytes;', hashlib.sha256(archive.read_bytes()).hexdigest())
