#!/usr/bin/env python3
"""Build the host and edition DKMS matrix inside a disposable container only."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

root = Path('/validation')
inputs = root / 'dkms-inputs'
release = sys.argv[1]
headers = root / 'headers/usr/src' / ('linux-headers-' + release)
results = []
modules = Path('/lib/modules') / release
modules.mkdir(parents=True, exist_ok=True)
(modules / 'build').symlink_to(headers)
Path('/usr/src').mkdir(exist_ok=True)
Path('/boot').mkdir(exist_ok=True)
(Path('/boot') / ('config-' + release)).symlink_to(headers / '.config')
keys = root / 'dkms-keys'
keys.mkdir()
subprocess.run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-days', '2', '-subj', '/CN=Sparky migration DKMS test/', '-keyout', str(keys / 'key.pem'),
    '-outform', 'DER', '-out', str(keys / 'cert.der')], check=True, stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL)
(keys / 'key.pem').chmod(0o600)
Path('/etc/dkms/framework.conf.d').mkdir(parents=True, exist_ok=True)
Path('/etc/dkms/framework.conf.d/99-migration-test.conf').write_text(
    f'mok_signing_key="{keys}/key.pem"\nmok_certificate="{keys}/cert.der"\n')
compat = inputs / 'compat-package.deb'
metadata = json.loads((inputs / 'compat-package.json').read_text())
assert hashlib.sha256(compat.read_bytes()).hexdigest() == metadata['sha256']
with (root / 'compat-install.log').open('w') as stream:
    subprocess.run(['dpkg', '-i', str(compat)], check=True, stdout=stream, stderr=subprocess.STDOUT)
assert subprocess.check_output(['dpkg-query', '-W', '-f=${Status}',
    'sparky-stereo-dkms-compat'], text=True).strip() == 'install ok installed'
cases = json.loads((inputs / 'cases.json').read_text())
for case in cases:
    label, name, version = case['label'], case['name'], case['version']
    work = root / 'dkms' / label
    work.mkdir(parents=True)
    source = work / 'src' / (name + '-' + version)
    public_source = Path('/usr/src') / source.name
    assert not public_source.exists()
    # Reproduce installed packages: dependency probes use find /usr/src/nvidia-*
    # without following directory symlinks. Keep this path a real directory.
    shutil.copytree(inputs / label, public_source, symlinks=True)
    source.parent.mkdir(parents=True, exist_ok=True)
    source.symlink_to(public_source)
    watched = ['nvfs-core.c', 'nvfs-batch.c'] if name == 'nvidia-fs' else []
    source_hashes = {f: hashlib.sha256((public_source / f).read_bytes()).hexdigest() for f in watched}
    tree = work / 'dkms'
    tree.mkdir()
    dependency_ok = True
    if name == 'nvidia-fs':
        # BUILD_DEPENDS requires installed NVIDIA state. It is installed ONLY in
        # this disposable container, then copied into this fresh DKMS database.
        prior = next((r for r in results if r['name'] == 'nvidia'), None)
        dependency_ok = bool(prior and prior['passed'])
        if dependency_ok:
            shutil.copytree(root / 'dkms/nvidia/dkms/nvidia', tree / 'nvidia', symlinks=True)
    command = ['dkms', '--dkmstree', str(tree), '--sourcetree', str(work / 'src')]
    log = work / 'result.log'
    with log.open('w') as stream:
        print(json.dumps(case), file=stream, flush=True)
        rc = 0 if dependency_ok else 13
        if rc == 0:
            rc = subprocess.run(command + ['add', '-m', name, '-v', version],
                                stdout=stream, stderr=subprocess.STDOUT).returncode
        if rc == 0:
            rc = subprocess.run(command + ['build', '-m', name, '-v', version,
                '-k', release, '-j', '4', '--verbose'], stdout=stream, stderr=subprocess.STDOUT).returncode
        if rc == 0 and name == 'nvidia':
            rc = subprocess.run(command + ['install', '-m', name, '-v', version,
                '-k', release], stdout=stream, stderr=subprocess.STDOUT).returncode
            if rc == 0:
                subprocess.run(['depmod', '-a', release], check=True,
                               stdout=stream, stderr=subprocess.STDOUT)
                found_version = subprocess.check_output(
                    ['modinfo', '-F', 'version', '-k', release, 'nvidia'], text=True).strip()
                assert found_version == version, (found_version, version)
    artifacts = sorted((tree / name / version / release / 'x86_64/module').glob('*.ko*'))
    checks = []
    for artifact in artifacts:
        def field(key):
            return subprocess.check_output(['modinfo', '-F', key, str(artifact)], text=True).strip()
        vermagic, signer, signature = field('vermagic'), field('signer'), field('signature')
        checks.append(dict(file=artifact.name, sha256=hashlib.sha256(artifact.read_bytes()).hexdigest(),
            vermagic=vermagic, signer=signer, has_signature=bool(signature),
            passed=vermagic.split()[0] == release and signer == 'Sparky migration DKMS test' and bool(signature)))
    # Read expected artifacts from the actual trusted dkms.conf, inside this
    # isolated environment. Do not infer success from an empty find result.
    query = 'source "$1"; printf "%s\\n" "${#BUILT_MODULE_NAME[@]}"'
    expected = int(subprocess.check_output(['bash', '-c', query, 'dkms-conf', str(source / 'dkms.conf')], text=True).strip())
    passed = rc == 0 and len(checks) == expected and expected > 0 and all(c['passed'] for c in checks)
    source_unchanged = all(hashlib.sha256((public_source / f).read_bytes()).hexdigest() == h
                           for f, h in source_hashes.items())
    overlay_applied = None
    if name == 'nvidia-fs':
        logs = list((tree / name / version).rglob('make.log'))
        overlay_applied = any('Applying patch sparky-nvidia-fs-public-lock-header.patch' in p.read_text(errors='replace') for p in logs)
        passed = passed and source_unchanged and overlay_applied
    result = dict(label=label, name=name, version=version, exit_code=rc, passed=passed,
        vendor_source_unchanged=source_unchanged, compatibility_patch_applied=overlay_applied,
        expected_modules=expected, artifacts=checks, dependency_satisfied=dependency_ok,
        log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
    results.append(result)
    (root / 'dkms-results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(label, 'PASS' if passed else 'FAIL', flush=True)
raise SystemExit(not all(r['passed'] for r in results))
