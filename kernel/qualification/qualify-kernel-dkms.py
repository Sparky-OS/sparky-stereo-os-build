#!/usr/bin/env python3
"""Use exact candidate DKMS payloads and the host's other installed module sources."""
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
out = base / 'kernel-qualification' / ('harness-rehearsal' if rehearsal else flavour)
assert out.is_dir(), 'Run the boot input staging first'
metadata = json.loads((out / 'inputs.json').read_text())
assert metadata['rehearsal'] == rehearsal
release = metadata['release']
tools = json.loads((base / 'kernel-dkms-tools/status.json').read_text())
assert tools['passed']
actual_image = subprocess.check_output(['docker', 'image', 'inspect', tools['image'],
                                       '--format', '{{.Id}}'], text=True).strip()
assert actual_image == tools['image_id']
inputs = out / 'dkms-inputs'
inputs.mkdir(exist_ok=False)
(inputs / 'validation-tools.json').write_text(json.dumps(tools, indent=2) + '\n')
progress = json.loads((notes / 'migration-progress.json').read_text())
packages = ['nvidia-kernel-open-dkms-stereo3d', 'xpadneo-dkms',
            'hid-tmff2-dkms', 'new-lg4ff-dkms', 'hid-fanatecff-dkms']
cases = []
for package in packages:
    archives = [Path(r['archive']) for r in progress['archives'] if r['Package'] == package]
    assert len(archives) == 1, package
    archive = archives[0]
    staged = inputs / ('extract-' + package)
    subprocess.run(['dpkg-deb', '-x', str(archive), str(staged)], check=True)
    roots = list((staged / 'usr/src').glob('*/dkms.conf'))
    assert len(roots) == 1, roots
    source = roots[0].parent
    # Package labels are stable. Read only literal identity declarations here;
    # the complete config is evaluated later inside the disposable container.
    import re
    conf = (source / 'dkms.conf').read_text()
    values = {}
    for key in ['PACKAGE_NAME', 'PACKAGE_VERSION']:
        match = re.search(r'^' + key + r'=[\"\']?([^\"\'\s]+)[\"\']?\s*$', conf, re.M)
        assert match, (package, key)
        values[key] = match[1]
    label = 'nvidia' if package.startswith('nvidia-') else package
    shutil.move(source, inputs / label)
    shutil.rmtree(staged)
    cases.append(dict(label=label, name=values['PACKAGE_NAME'], version=values['PACKAGE_VERSION'],
        archive=str(archive), archive_sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
        rt_override_already_in_package='IGNORE_PREEMPT_RT_PRESENCE=1' in conf))
for name, version in [('acpi-call', '1.2.2'), ('r8168', '8.055.00'),
                      ('v4l2loopback', '0.15.4'), ('nvidia-fs', '2.29.4')]:
    source = Path('/usr/src') / (name + '-' + version)
    assert (source / 'dkms.conf').is_file(), source
    shutil.copytree(source, inputs / name, symlinks=True)
    cases.append(dict(label=name, name=name, version=version, installed_source=str(source)))
compat = base / 'scripts/sparky-stereo-dkms-compat/sparky-stereo-dkms-compat_0.1.0+lc1_all.deb'
assert compat.is_file()
shutil.copy2(compat, inputs / 'compat-package.deb')
(inputs / 'compat-package.json').write_text(json.dumps(dict(
    archive=str(compat), sha256=hashlib.sha256(compat.read_bytes()).hexdigest(),
    reason='Version-scoped DKMS build-copy overlay; installed vendor source unchanged'), indent=2) + '\n')
inventory = {}
for p in sorted(inputs.rglob('*')):
    if p.is_symlink():
        inventory[str(p.relative_to(inputs))] = {'link': str(p.readlink())}
    elif p.is_file():
        inventory[str(p.relative_to(inputs))] = {'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
(inputs / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
(inputs / 'source-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
shutil.copy2((cfg.TREE / 'kernel/qualification/kernel-dkms-inner.py'), inputs / 'run.py')
host_status = subprocess.check_output(['/usr/sbin/dkms', 'status'], text=True)
(inputs / 'host-dkms-status.txt').write_text(host_status)
installed = {line.split(',', 1)[0] for line in host_status.splitlines() if ': installed' in line}
covered = {case['name'] + '/' + case['version'] for case in cases}
assert installed <= covered, ('Host DKMS matrix changed', sorted(installed - covered))
name = 'sparky-lc-dkms-check-' + flavour
command = ['docker', 'run', '--rm', '--name', name, '--cpus', '4', '--memory', '12g',
           '-v', str(out) + ':/validation', tools['image'],
           'python3', '/validation/dkms-inputs/run.py', release]
scope = ('Candidate DKMS packages against existing build-8 headers; NOT build-9 qualification'
         if rehearsal else 'isolated module builds; no host DKMS writes')
report = dict(state='queued', scope=scope, release=release)
(out / 'dkms-status.json').write_text(json.dumps(report, indent=2) + '\n')
with (out / 'dkms-driver.log').open('w') as log:
    process = start_build(command, name, log)
    report['state'] = 'running'
    (out / 'dkms-status.json').write_text(json.dumps(report, indent=2) + '\n')
    stopped = False
    while process.poll() is None:
        if shutil.disk_usage(base).free < 12 * 1024**3:
            subprocess.run(['docker', 'stop', '-t', '20', name], check=False)
            stopped = True
            break
        time.sleep(5)
    rc = process.wait()
report.update(state='passed' if rc == 0 else 'needs-repair', exit_code=rc, disk_floor_stop=stopped)
(out / 'dkms-status.json').write_text(json.dumps(report, indent=2) + '\n')
print(flavour, 'DKMS', report['state'], flush=True)
raise SystemExit(rc)
