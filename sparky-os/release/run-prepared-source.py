#!/usr/bin/env python3
"""Build an explicitly prepared, retained lc1 source descriptor in isolation."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
kit = (cfg.TREE / 'sparky-os')
sys.path.insert(0, str(kit))
from lean.package import stanzas

descriptor = Path(sys.argv[1]).resolve()
fields = next(stanzas(descriptor.read_text()))
name, version = fields['source'], fields['version']
if name not in ('filmcraft', 'photocraft', 'vibe') or not version.endswith('+lc1'):
    raise SystemExit('Review the prepared-source recipe for this package')
vendor_release = name == 'vibe'
work = base / 'scripts/vibe' if vendor_release else base / 'jobs' / (name + '-amd64')
if work.exists():
    raise SystemExit('Existing job: review it rather than replacing its evidence')
if shutil.disk_usage(base).free < (14 if vendor_release else 26) * 1024**3:
    raise SystemExit('Disk below prepared-build start floor')
work.mkdir()
shutil.copy2(descriptor, work / descriptor.name)
for line in fields['checksums-sha256'].splitlines():
    if not line.strip():
        continue
    sha, size, filename = line.split()
    source = descriptor.parent / filename
    with source.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != sha or source.stat().st_size != int(size):
        raise SystemExit('Prepared source integrity failure')
    shutil.copy2(source, work / filename)
recipe = '''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
printf 'deb [trusted=yes] file:/repo ./\\n' > /etc/apt/sources.list.d/edition.list
printf 'Package: *\\nPin: release o=Sparky Stereo OS\\nPin-Priority: 1001\\n' > /etc/apt/preferences.d/edition
cd /work
dpkg-source -x "$TASK_DSC" source
apt-get -y update
apt-get -y --no-install-recommends build-dep /work/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd source
runuser -u builder -- dpkg-buildpackage -us -uc -j4
if [ "$TASK_KIND" = signed-upstream-release ]; then
    python3 - <<'VENDOR_PROOF'
from pathlib import Path
import hashlib, io, json, subprocess, tarfile
origin = json.loads(Path('debian/upstream-binary.json').read_text())
archive = Path(origin['archive'])
assert not origin['native_compilation_performed']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == origin['sha256']
comparisons = {}
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(archive)]))) as files:
    for name in ['vibe', 'vibe-server']:
        path = 'usr/bin/' + name
        item = next(m for m in files.getmembers() if m.name.removeprefix('./') == path)
        upstream = files.extractfile(item).read()
        final = (Path('debian/vibe') / path).read_bytes()
        assert final == upstream, path
        comparisons[path] = hashlib.sha256(final).hexdigest()
origin['unchanged_executables_sha256'] = comparisons
Path('../upstream-binary-proof.json').write_text(json.dumps(origin, indent=2) + '\\n')
VENDOR_PROOF
else
    cp .sparky-lc/source.json ../native-source.json
    tar -cJf ../native-authored-evidence.tar.xz .sparky-lc
fi
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
'''
(work / 'run.sh').write_text(recipe)
status = {'source': name, 'version': version, 'architecture': 'amd64',
          'state': 'building', 'archives': [],
          'source_descriptor_sha256': hashlib.sha256(descriptor.read_bytes()).hexdigest()}
(work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
container = 'sparky-lc-' + name + '-amd64'
command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--name', container, '--cpus', '4',
           '-e', 'TASK_DSC=' + descriptor.name, '-v', str(work) + ':/work',
           '-e', 'TASK_KIND=' + ('signed-upstream-release' if vendor_release else 'native'),
           '-v', str(cfg.path('SPARKY_REPO_DIR')) + ':/repo:ro', '-v', str(kit) + ':/toolkit:ro',
           'sparky-lc-migration:20261020', 'bash', '/work/run.sh']
started, stopped = time.time(), False
with (work / 'build.log').open('w') as log:
    process = start_build(command, container, log)
    while process.poll() is None:
        if shutil.disk_usage(base).free < 12 * 1024**3:
            subprocess.run(['docker', 'stop', '-t', '20', container], check=False)
            stopped = True
            break
        time.sleep(5)
    result = process.wait()
status.update({'state': 'candidate-needs-review' if result == 0 else 'needs-repair',
               'exit_code': result, 'disk_floor_stop': stopped,
               'seconds': round(time.time() - started, 1),
               'archives': sorted(p.name for p in work.glob('*+lc1_*.deb'))})
(work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
print(name, status['state'], flush=True)
if result:
    raise SystemExit(result)
if not vendor_release:
    subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/prune-completed-build.py')),
                    name + '-amd64'], check=True)
