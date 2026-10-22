#!/usr/bin/env python3
"""Build the three audited kernel flavours serially after the packaging smoke passes.

This stages candidates only. Publication, boot/DKMS tests and host installation
remain separate gates. No host kernel or boot entry is changed here.
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

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
kit = cfg.TREE
keydir = cfg.path('SPARKY_SECUREBOOT_DIR')
sys.path.insert(0, str(kit / 'sparky-os'))
from lean.package import stanzas

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--start-at', choices=['base', 'v3', 'rt'], default='base')
args = parser.parse_args()
flavours = ['base', 'v3', 'rt']


def qualification_passed(flavour, job):
    """Retain repairable objects and stop propagation of a broken common recipe."""
    queue_status = base / 'kernel-qualification-queue/status.json'
    try:
        failed = json.loads(queue_status.read_text()).get('state') == 'needs-repair'
    except (FileNotFoundError, json.JSONDecodeError):
        failed = False
    if failed:
        raise RuntimeError('Kernel qualification queue needs repair; later flavours not started')
    qualification = base / 'kernel-qualification' / flavour
    for path in [qualification / 'status.json', qualification / 'dkms-status.json']:
        try:
            state = json.loads(path.read_text()).get('state')
        except (FileNotFoundError, json.JSONDecodeError):
            return False
        if state == 'needs-repair':
            raise RuntimeError(flavour + ': qualification failed; object cache retained, later flavours not started')
        if state != 'passed':
            return False
    inputs = json.loads((qualification / 'inputs.json').read_text())
    for archive in inputs['archives'].values():
        path = job / Path(archive['path']).name
        assert hashlib.sha256(path.read_bytes()).hexdigest() == archive['sha256'], \
            'Qualification belongs to another candidate: ' + str(path)
    return True


for previous in flavours[:flavours.index(args.start_at)]:
    job = base / 'jobs' / ('linux-stereo-' + previous + '-amd64')
    completed = json.loads((job / 'status.json').read_text())
    assert completed['state'] == 'candidate-needs-review' and completed['exit_code'] == 0
    descriptor = job / f'linux-stereo-{previous}_7.3.0~rc6-9+lc1.dsc'
    assert hashlib.sha256(descriptor.read_bytes()).hexdigest() == completed['source_descriptor_sha256']
    assert qualification_passed(previous, job), 'Previous flavour must qualify before continuing'

while True:
    status_path = base / 'kernel-smoke/status.json'
    if not status_path.exists():
        time.sleep(10)
        continue
    smoke = json.loads(status_path.read_text())
    if smoke['state'] == 'smoke-complete':
        break
    if smoke['state'] not in ('queued', 'building'):
        raise SystemExit('Kernel smoke needs repair; full builds remain stopped')
    time.sleep(10)

certificate = subprocess.check_output(
    ['openssl', 'x509', '-in', str(keydir / 'cert.pem'), '-noout', '-fingerprint', '-sha256'], text=True)
expected = 'D9:87:08:1B:FE:6F:F0:BF:BC:03:5C:AC:B2:25:9F:60:7E:E4:6B:0B:AD:1C:44:AB:34:99:55:5D:5F:27:D9:77'
assert certificate.strip().endswith(expected), 'Review edition certificate change'
assert (keydir / 'key.pem').is_file()

for flavour in flavours[flavours.index(args.start_at):]:
    name = 'linux-stereo-' + flavour
    work = base / 'jobs' / (name + '-amd64')
    if work.exists():
        raise SystemExit(f'{name}: existing job needs review; never overwrite it')
    # A full kernel carries the authored source, object tree, nested and final
    # archives. Do not start at the small native-package threshold.
    # Avoid overlapping the full kernel's object/package peak with other large
    # native builds. Their compiled scratch is retired after verification.
    heavy_jobs = ['digikam-amd64', 'mesa-amd64', 'mesa-i386', 'wine-amd64',
                  'wine-i386', 'sparky-stereo-browser-amd64', 'qemu-amd64']
    while True:
        preflight = base / 'kernel-source-preflight/status.json'
        ready = preflight.exists() and json.loads(preflight.read_text()).get('passed')
        for job in heavy_jobs:
            report = base / 'jobs' / job / 'status.json'
            ready = ready and report.exists() and json.loads(report.read_text())['state'] == 'candidate-needs-review'
        if ready and shutil.disk_usage(base).free >= 50 * 1024**3:
            break
        time.sleep(10)
    origin = base / 'kernel-sources' / flavour
    if not origin.exists():
        subprocess.run([sys.executable, str((cfg.TREE / 'kernel/qualification/prepare-kernel-source.py')), flavour], check=True)
    source = origin / 'source'
    for filename in ['build.sh', 'stage.sh', 'check-module-signature.py', 'check-source-consumers.py']:
        assert (source / 'debian' / filename).read_bytes() == (kit / 'kernel/lean' / filename).read_bytes(), \
            'Prepared source recipe changed; repackage before building'
    descriptor = origin / f'{name}_7.3.0~rc6-9+lc1.dsc'
    fields = next(stanzas(descriptor.read_text()))
    work.mkdir()
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
runuser -u builder -- env SPARKY_SIGNING_KEY_DIR=/signing dpkg-buildpackage -us -uc -b -j4
cp .sparky-lc/source.json /work/native-source.json
tar -cJf /work/native-authored-evidence.tar.xz .sparky-lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
find build/certs -name signing_key.pem -o -name x509.genkey > /work/key-remnants.txt
test ! -s /work/key-remnants.txt
'''
    (work / 'run.sh').write_text(recipe)
    status = dict(source=name, version='7.3.0~rc6-9+lc1', architecture='amd64', state='queued',
                  archives=[], certificate_sha256=expected, boot_dkms_qualification='pending',
                  source_descriptor_sha256=hashlib.sha256(descriptor.read_bytes()).hexdigest())
    (work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
    container = 'sparky-lc-kernel-' + flavour
    command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--name', container,
               '--cpus', '4', '--memory', '32g', '-v', str(work) + ':/work',
               '-v', str(keydir) + ':/signing:ro',
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
    if result:
        raise SystemExit(result)
    print(name, 'waiting for isolated boot and DKMS qualification; object cache retained', flush=True)
    while not qualification_passed(flavour, work):
        time.sleep(10)
    status['boot_dkms_qualification'] = 'passed'
    (work / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
    subprocess.run([sys.executable, str((cfg.TREE / 'sparky-os/release/prune-completed-build.py')), name + '-amd64'], check=True)
