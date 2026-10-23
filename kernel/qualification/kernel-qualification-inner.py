#!/usr/bin/env python3
"""Run the retained kernel feature probes inside the disposable validation container."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

root = Path('/validation')
inputs = Path('/inputs')
release = sys.argv[1]
headers = root / 'headers/usr/src' / ('linux-headers-' + release)
kernel = root / 'image/boot' / ('vmlinuz-' + release)
results = []


def run(label, command, expected=(), env=None):
    log = root / (label + '.log')
    with log.open('w') as stream:
        rc = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                            env=env).returncode
    text = log.read_text(errors='replace')
    summaries = re.findall(r'^PASS\s+(\S+)\s+\(', text, re.M)
    # Use the bench's verdict: an expected refusal (for example hibernation
    # under lockdown) can contain a negative guest probe and still be correct.
    failed = bool(re.search(r'^FAIL\s', text, re.M))
    passed = rc == 0 and not failed and all(x in summaries for x in expected)
    results.append(dict(label=label, exit_code=rc, passed=passed,
                        expected_scenarios=list(expected), summaries=summaries,
                        log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
    (root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(label, 'PASS' if passed else 'FAIL', flush=True)
    return passed


for required in [headers / '.config', headers / 'Module.symvers',
                 headers / 'scripts/sign-file', headers / 'vmlinux', kernel]:
    assert required.is_file(), required
assert os.access('/dev/kvm', os.R_OK | os.W_OK), 'KVM is required for this matrix'
assert (inputs / 'guest/bin/scx_simple').is_file()
assert (inputs / 'settings/usr/lib/sysctl.d/70-sparky-stereo.conf').is_file()
# SPARKY_UNSIGNED=1: the image is still unsigned (before the release coordinator signs it). The bench then signs it with
# its own throw-away key, exactly as it does for any kernel it is given, and the edition certificate is not involved.
unsigned_mode = os.environ.get('SPARKY_UNSIGNED') == '1'
if unsigned_mode:
    assert run('image-unsigned-as-built', ['sh', '-c', '! sbverify --list "$1" 2>&1 | grep -q "^signature 1"', 'x', str(kernel)])
    env = dict(os.environ, KEXEC_UNSIGNED=str(kernel))
    signing = []
else:
    assert run('image-signature', ['sbverify', '--cert', '/inputs/edition.pem', str(kernel)])
    unsigned = root / 'kernel.unsigned'
    shutil.copy2(kernel, unsigned)
    assert run('unsigned-control', ['sbattach', '--remove', str(unsigned)])
    env = dict(os.environ, KEXEC_UNSIGNED=str(unsigned))
    signing = ['--kernel-signed', '--db-cert', '/inputs/edition.pem']
bench = [str(inputs / 'bench/bench'), '--work', str(root / 'boot-work'),
         '--kernel', str(kernel)] + signing + [
         '--ksrc', str(headers), '--modules-dir', str(root / 'image'),
         '--mem', '2048', '--cpus', '4', '--timeout', '600', '--accel', 'kvm']
assert run('doctor', [str(inputs / 'bench/bench'), '--work', str(root / 'doctor'), 'doctor'])
scenarios = ['policy', 'tpm', 'hibernate', 'lockdown-integrity', 'lockdown-confidentiality']
run('secure-boot', bench + ['run'] + scenarios, scenarios, env)
run('mok-policy', bench + ['--module-trust', 'mok', 'run', 'policy'], ['policy'], env)
settings = ['--guest-sysctl', '/inputs/settings/usr/lib/sysctl.d/70-sparky-stereo.conf']
run('settings-hibernate', bench + settings + ['run', 'hibernate'], ['hibernate'], env)
run('features', bench + ['--load-modules', 'virtio_blk efivarfs binder_linux ntsync tcp_bbr3 adios',
    '--guest-script', '/inputs/features.sh', '--guest-dir', '/inputs/guest', 'run', 'custom'],
    ['custom'], env)
run('settings-kexec', bench + settings + ['run', 'kexec'], ['kexec'], env)
run('legacy-bios', bench + ['--bios', 'run', 'policy'], ['policy'], env)

# The old feature script uses INFO for optional tools. This release matrix
# requires those inputs, and cannot silently turn their absence into a pass.
features = (root / 'features.log').read_text(errors='replace')
mandatory = ['secure_boot', 'btf_vmlinux', 'btf_modules', 'sched_ext_load',
             'sysctl_sched_bore', 'sysctl_sched_poc_selector', 'binderfs',
             'dev_ntsync', 'tcp_bbr3', 'module_virtio_blk', 'module_binder_linux',
             'module_ntsync', 'module_tcp_bbr3', 'module_adios']
missing = [key for key in mandatory if not re.search(r'^PASS\s+' + key + r'\s', features, re.M)]
results.append(dict(label='required-features', passed=not missing, missing=missing))
(root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
raise SystemExit(not all(r['passed'] for r in results))
