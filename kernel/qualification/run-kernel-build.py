#!/usr/bin/env python3
"""Build one prepared Lean Code kernel source package unsigned, in a disposable container.

    run-kernel-build.py FLAVOUR --counter N [--memory 16g]

prepare-kernel-source.py has already written SPARKY_MIGRATION_WORK/kernel-sources/FLAVOUR. The packages stay unsigned
(no SPARKY_SIGNING_KEY_DIR is mounted): the release coordinator signs the image afterwards (kernel/qualification/sign-kernel-image.py).
Module signing uses Kbuild's own key, which exists only during the build. The tree of a finished build is pruned by
the caller once its packages are retained.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg
from build_slots import start_build

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('flavour', choices=['base', 'v3', 'rt'])
parser.add_argument('--counter', required=True)
parser.add_argument('--packaging-revision')
parser.add_argument('--memory', default='16g')
args = parser.parse_args()
base = cfg.path('SPARKY_MIGRATION_WORK')
kit = cfg.TREE
flavour = args.flavour
version = '7.3.0~rc6-' + args.counter + ('.' + args.packaging_revision if args.packaging_revision else '') + '+lc1'
name = 'linux-stereo-' + flavour
origin = base / 'kernel-sources' / flavour
work = base / 'jobs' / (name + '-amd64')
if work.exists():
    raise SystemExit(f'{name}: existing job needs review; never overwrite it')
source = origin / 'source'
for filename in ['build.sh', 'stage.sh', 'check-module-signature.py', 'check-source-consumers.py']:
    assert (source / 'debian' / filename).read_bytes() == (kit / 'kernel/lean' / filename).read_bytes(), \
        'Prepared source recipe changed; repackage before building'
recipe_dir = source / 'debian/kernel-recipe'
for relative in ['libc-dev.py', 'maint/image.preinst', 'maint/image.postinst', 'maint/image.prerm', 'maint/image.postrm']:
    assert (recipe_dir / relative).read_bytes() == (kit / 'kernel/lean' / relative).read_bytes(), \
        'Prepared source recipe changed; repackage before building'
descriptor = origin / f'{name}_{version}.dsc'
sys.path.insert(0, str(kit / 'sparky-os'))
from lean.package import stanzas
fields = next(stanzas(descriptor.read_text()))
work.mkdir(parents=True)
(work / descriptor.name).hardlink_to(descriptor)
for row in fields['checksums-sha256'].splitlines():
    if not row.strip():
        continue
    expected_sha, size, filename = row.split()
    archive = origin / filename
    assert archive.stat().st_size == int(size)
    with archive.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').hexdigest() == expected_sha
    (work / filename).hardlink_to(archive)
shutil.move(source, work / 'source')
recipe = '''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
apt-get -y update
apt-get -y --no-install-recommends build-dep /work/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- dpkg-buildpackage -us -uc -b -j4
cp .sparky-lc/source.json /work/native-source.json
tar -cJf /work/native-authored-evidence.tar.xz .sparky-lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
find build/certs -name signing_key.pem -o -name x509.genkey > /work/key-remnants.txt
test ! -s /work/key-remnants.txt
'''
(work / 'run.sh').write_text(recipe)
status = dict(source=name, version=version, architecture='amd64', state='queued', archives=[],
              signed=False, source_descriptor_sha256=hashlib.sha256(descriptor.read_bytes()).hexdigest())
(work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
container = 'sparky-lc-kernel-' + flavour
command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--name', container,
           '--cpus', '4', '--memory', args.memory, '-v', str(work) + ':/work',
           '-v', str(kit / 'sparky-os') + ':/toolkit:ro',
           'sparky-lc-migration:20261020', 'bash', '/work/run.sh']
with (work / 'build.log').open('w') as log:
    process = start_build(command, container, log)
    status['state'] = 'building'
    (work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
    start, stopped = time.time(), False
    while process.poll() is None:
        if shutil.disk_usage(base).free < 12 * 1024**3:
            subprocess.run(['docker', 'stop', '-t', '20', container], check=False)
            stopped = True
            break
        time.sleep(5)
    result = process.wait()
status.update(state='candidate-needs-review' if result == 0 else 'needs-repair',
              exit_code=result, disk_floor_stop=stopped, seconds=round(time.time() - start, 1),
              archives=sorted(p.name for p in work.glob('*+lc1_*.deb')))
(work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
print(name, status['state'], flush=True)
raise SystemExit(result)
