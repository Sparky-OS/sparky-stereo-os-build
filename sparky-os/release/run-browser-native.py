#!/usr/bin/env python3
"""Build the retained browser export with its pinned accepted compiler bundle."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build

base = cfg.path('SPARKY_MIGRATION_WORK')
origin = base / 'browser-source'
source = origin / 'source'
work = base / 'jobs/sparky-stereo-browser-amd64'
descriptor = origin / 'sparky-stereo-browser_6.7.5-0+stereo3d5+lc1.dsc'
while not descriptor.exists() or shutil.disk_usage(base).free < 30 * 1024**3:
    time.sleep(10)
work.mkdir()
for path in origin.glob('sparky-stereo-browser_*'):
    if path.is_file():
        (work / path.name).hardlink_to(path)
recipe = '''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
printf 'deb [trusted=yes] file:/repo ./\\n' > /etc/apt/sources.list.d/edition.list
printf 'Package: *\\nPin: release o=Sparky Stereo OS\\nPin-Priority: 1001\\n' > /etc/apt/preferences.d/edition
apt-get -y update
apt-get -y --no-install-recommends build-dep /work/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- env SPARKY_BROWSER_TOOLCHAIN_ROOT=/browser-toolchains dpkg-buildpackage -us -uc -b -j4
cp .sparky-lc/source.json /work/native-source.json
tar -cJf /work/native-authored-evidence.tar.xz .sparky-lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
'''
(work / 'run.sh').write_text(recipe)
status = {'source': 'sparky-stereo-browser', 'version': '6.7.5-0+stereo3d5+lc1',
          'architecture': 'amd64', 'state': 'queued', 'archives': [],
          'source_descriptor_sha256': hashlib.sha256(descriptor.read_bytes()).hexdigest(),
          'headless_stereo_bench': 'required after successful package build'}
(work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
container = 'sparky-lc-browser-amd64'
command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--name', container,
           '--cpus', '4', '--memory', '32g', '-v', str(work) + ':/work',
           '-v', str(source) + ':/work/source',
           '-v', str(cfg.path('SPARKY_BROWSER_WORK') / 'home') + ':/browser-toolchains:ro',
           '-v', str(cfg.path('SPARKY_REPO_DIR')) + ':/repo:ro',
           '-v', str(cfg.TREE / 'sparky-os') + ':/toolkit:ro',
           'sparky-lc-migration:20261020', 'bash', '/work/run.sh']
stopped = False
with (work / 'build.log').open('w') as log:
    process = start_build(command, container, log)
    status['state'] = 'building'
    (work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
    start = time.time()
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
print(status)
raise SystemExit(result)
