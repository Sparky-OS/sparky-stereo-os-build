#!/usr/bin/env python3
"""Validate one completed build-9 kernel without installing it on the host."""
from pathlib import Path
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
flavour = sys.argv[1]
assert flavour in ['base', 'v3', 'rt']
rehearsal = sys.argv[2:] == ['--rehearse-existing']
assert not sys.argv[2:] or rehearsal
assert not rehearsal or flavour == 'base'
job = base / 'jobs' / ('linux-stereo-' + flavour + '-amd64')
if not rehearsal:
    status = json.loads((job / 'status.json').read_text())
    assert status['state'] == 'candidate-needs-review' and status['exit_code'] == 0
tools = json.loads((base / 'kernel-validation-tools/status.json').read_text())
assert tools['passed']
image_id = subprocess.check_output(['docker', 'image', 'inspect', tools['image'],
                                   '--format', '{{.Id}}'], text=True).strip()
assert image_id == tools['image_id'], 'Validation tool image changed'
out = base / 'kernel-qualification' / ('harness-rehearsal' if rehearsal else flavour)
out.mkdir(parents=True, exist_ok=False)
inputs = out / 'inputs'
inputs.mkdir()
old = (cfg.path('SPARKY_INPUTS_DIR') / 'kernel-soul/work')
shutil.copytree(cfg.TREE / 'kernel/qualification/hibernate-bench', inputs / 'bench')
shutil.copytree(old / 'bench-run/r2/initrd-tree/guest', inputs / 'guest')
shutil.copy2(cfg.TREE / 'kernel/qualification/guest/features.sh', inputs / 'features.sh')
shutil.copy2(cfg.TREE / 'kernel/qualification/guest/modules.sh', inputs / 'modules.sh')
certificate = (base / 'kernel-signature-investigation/embedded-cert.pem' if rehearsal
               else (cfg.path('SPARKY_SECUREBOOT_DIR') / 'cert.pem'))
fingerprint = subprocess.check_output(['openssl', 'x509', '-in', str(certificate),
    '-noout', '-fingerprint', '-sha256'], text=True).strip()
expected = ('6F:78:C9:36:7E:31:33:1F:3B:AA:74:D0:2F:05:B1:B2:DF:36:D8:B8:5A:C6:88:94:EB:0B:4C:53:15:60:AA:A6'
            if rehearsal else 'D9:87:08:1B:FE:6F:F0:BF:BC:03:5C:AC:B2:25:9F:60:7E:E4:6B:0B:AD:1C:44:AB:34:99:55:5D:5F:27:D9:77')
assert fingerprint.endswith(expected)
shutil.copy2(certificate, inputs / 'edition.pem')
shutil.copy2((cfg.TREE / 'kernel/qualification/kernel-qualification-inner.py'), inputs / 'run.py')
progress = json.loads((notes / 'migration-progress.json').read_text())
settings = [Path(r['archive']) for r in progress['archives']
            if r['Package'] == 'sparky-stereo-kernel-settings']
assert len(settings) == 1
subprocess.run(['dpkg-deb', '-x', str(settings[0]), str(inputs / 'settings')], check=True)
archives = {}
for kind in ['image', 'headers']:
    if rehearsal:
        paths = list(cfg.path('SPARKY_REPO_DIR').glob(
            'linux-' + kind + '-7.3.0-rc6-stereo3d8_*_amd64.deb'))
    else:
        paths = list(job.glob('linux-' + kind + '-*+lc1_amd64.deb'))
    paths = [p for p in paths if '-lc-hr_' not in p.name]
    assert len(paths) == 1, paths
    p = paths[0]
    archives[kind] = dict(path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest())
    subprocess.run(['dpkg-deb', '-x', str(p), str(out / kind)], check=True)
kernels = list((out / 'image/boot').glob('vmlinuz-*'))
assert len(kernels) == 1
release = kernels[0].name.removeprefix('vmlinuz-')
assert release == '7.3.0-rc6-stereo3d8' if rehearsal else 'stereo3d10' in release
inventory = {}
for p in sorted(inputs.rglob('*')):
    if p.is_symlink():
        inventory[str(p.relative_to(inputs))] = {'link': str(p.readlink())}
    elif p.is_file():
        inventory[str(p.relative_to(inputs))] = {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                                                'mode': p.stat().st_mode & 0o777}
(out / 'inputs.json').write_text(json.dumps(dict(release=release, rehearsal=rehearsal, archives=archives,
    certificate_fingerprint=expected,
    certificate_scope='retired certificate for build-8 harness rehearsal ONLY' if rehearsal else 'current edition certificate',
    image=tools, settings_archive=str(settings[0]),
    settings_sha256=hashlib.sha256(settings[0].read_bytes()).hexdigest(),
    files=inventory), indent=2) + '\n')
name = 'sparky-lc-kernel-check-' + flavour
command = ['docker', 'run', '--rm', '--name', name, '--cpus', '4', '--memory', '8g',
           '--device', '/dev/kvm', '-v', str(out) + ':/validation',
           '-v', str(inputs) + ':/inputs:ro', tools['image'], 'python3', '/inputs/run.py', release]
scope = ('Harness rehearsal with existing build 8; NOT build-9 kernel qualification'
         if rehearsal else 'isolated boot/Secure Boot; no host installation')
report = dict(state='queued', scope=scope, release=release)
(out / 'status.json').write_text(json.dumps(report, indent=2) + '\n')
with (out / 'driver.log').open('w') as log:
    process = start_build(command, name, log)
    report['state'] = 'running'
    (out / 'status.json').write_text(json.dumps(report, indent=2) + '\n')
    stopped = False
    while process.poll() is None:
        if shutil.disk_usage(base).free < 12 * 1024**3:
            subprocess.run(['docker', 'stop', '-t', '20', name], check=False)
            stopped = True
            break
        time.sleep(5)
    rc = process.wait()
report.update(state='passed' if rc == 0 else 'needs-repair', exit_code=rc, disk_floor_stop=stopped)
(out / 'status.json').write_text(json.dumps(report, indent=2) + '\n')
print(flavour, report['state'], flush=True)
raise SystemExit(rc)
