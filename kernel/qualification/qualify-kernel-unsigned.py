#!/usr/bin/env python3
"""Boot a freshly built, still unsigned kernel in the validation guest and run the feature matrix, without any edition key.

    qualify-kernel-unsigned.py FLAVOUR DEBS_DIR OUT_DIR

DEBS_DIR holds the flavour's linux-image and linux-headers packages (not the -lc-hr companion). The guest is the one
qualify-kernel-boot.py uses; the bench signs the image with its own throw-away key (inner script, SPARKY_UNSIGNED=1).
This does not replace the run with the edition-signed image: the coordinator repeats qualify-kernel-boot.py after signing.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
import local_config as cfg

flavour, debs, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
assert flavour in ('base', 'v3', 'rt')
IMAGE = 'sparky-lc-kernel-checks-qemu:20261020'
repo = Path('/var/tmp/sparky-repo-current')
out.mkdir(parents=True, exist_ok=False)
inputs = out / 'inputs'
inputs.mkdir()
kit = cfg.TREE / 'kernel/qualification'
shutil.copytree(kit / 'hibernate-bench', inputs / 'bench')
shutil.copytree(cfg.path('SPARKY_INPUTS_DIR') / 'kernel-soul/work/bench-run/r2/initrd-tree/guest', inputs / 'guest')
shutil.copy2(kit / 'guest/features.sh', inputs / 'features.sh')
shutil.copy2(kit / 'guest/modules.sh', inputs / 'modules.sh')
shutil.copy2(kit / 'kernel-qualification-inner.py', inputs / 'run.py')
(inputs / 'edition.pem').write_text('unused in unsigned mode\n')
settings = next(repo.glob('pool/main/s/sparky-stereo-kernel-settings/sparky-stereo-kernel-settings_*_all.deb'))
subprocess.run(['dpkg-deb', '-x', str(settings), str(inputs / 'settings')], check=True)
archives = {}
for kind in ('image', 'headers'):
    paths = [p for p in debs.glob(f'linux-{kind}-*_amd64.deb') if '-lc-hr_' not in p.name]
    assert len(paths) == 1, paths
    archives[kind] = dict(path=str(paths[0]), sha256=hashlib.sha256(paths[0].read_bytes()).hexdigest())
    subprocess.run(['dpkg-deb', '-x', str(paths[0]), str(out / kind)], check=True)
release = next((out / 'image/boot').glob('vmlinuz-*')).name.removeprefix('vmlinuz-')
(out / 'inputs.json').write_text(json.dumps(dict(release=release, archives=archives, unsigned=True,
    settings=str(settings), image=IMAGE), indent=2) + '\n')
command = ['docker', 'run', '--rm', '--name', 'sparky-212-boot-' + flavour, '--cpus', '4', '--memory', '8g',
           '--device', '/dev/kvm', '-e', 'SPARKY_UNSIGNED=1', '-v', f'{out}:/validation', '-v', f'{inputs}:/inputs:ro',
           IMAGE, 'python3', '/inputs/run.py', release]
with (out / 'driver.log').open('w') as log:
    rc = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
(out / 'status.json').write_text(json.dumps(dict(state='passed' if rc == 0 else 'needs-repair', exit_code=rc,
    release=release, scope='isolated boot with the bench key; unsigned build; no host installation'), indent=2) + '\n')
print(flavour, 'passed' if rc == 0 else 'FAILED', 'exit', rc)
raise SystemExit(rc)
