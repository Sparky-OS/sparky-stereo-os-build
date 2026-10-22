#!/usr/bin/env python3
"""Run the disposable source-package smoke test with both disk guards."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import time
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg
from build_slots import start_build

parser = argparse.ArgumentParser()
parser.add_argument('--resume', action='store_true')
args = parser.parse_args()

base = (cfg.path('SPARKY_MIGRATION_WORK') / 'kernel-smoke')
source = (cfg.path('SPARKY_BUILD_SCRATCH') / 'sparky-lc-kernel-smoke-source')
container = 'sparky-lc-kernel-smoke'
while (shutil.disk_usage(base).free < 22 * 1024**3 or
       sum(n.startswith('sparky-lc-') for n in subprocess.check_output(
           ['docker', 'ps', '--format', '{{.Names}}'], text=True).splitlines()) >= 4):
    time.sleep(10)
if shutil.disk_usage(source).free < 3 * 1024**3:
    raise SystemExit('Build disk below smoke-test start floor')
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
'''
if args.resume:
    assert (source / 'debian/debhelper-build-stamp').is_file()
    assert json.loads((source / '.sparky-lc/source.json').read_text()).get('qualified')
    recipe = recipe.replace('dpkg-buildpackage -us -uc -b -j4', 'dpkg-buildpackage -us -uc -nc -b -j4')
(base / 'run.sh').write_text(recipe)
status = {'state': 'building', 'purpose': 'smoke test only; never publish these packages'}
(base / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--name', container,
           '--cpus', '4', '-v', str(base) + ':/work', '-v', str(source) + ':/work/source',
           '-v', str(cfg.TREE / 'sparky-os') + ':/toolkit:ro',
           'sparky-lc-migration:20261020', 'bash', '/work/run.sh']
start, stopped = time.time(), False
with (base / 'build.log').open('w') as log:
    process = start_build(command, container, log)
    while process.poll() is None:
        if (shutil.disk_usage(base).free < 12 * 1024**3 or
                shutil.disk_usage(source).free < 2 * 1024**3):
            subprocess.run(['docker', 'stop', '-t', '20', container], check=False)
            stopped = True
            break
        time.sleep(5)
    result = process.wait()
status.update(state='smoke-complete' if result == 0 else 'needs-repair',
              exit_code=result, disk_floor_stop=stopped,
              seconds=round(time.time() - start, 1))
(base / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
print(status)
raise SystemExit(result)
