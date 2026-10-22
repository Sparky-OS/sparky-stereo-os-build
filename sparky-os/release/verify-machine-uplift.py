#!/usr/bin/env python3
"""Read-only installed/boot preparation audit after the reviewed upgrade finishes."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('output', type=Path)
p.add_argument('--hostname', required=True)
args = p.parse_args()
assert socket.gethostname() == args.hostname
completion = args.output / ('refresh-status.json' if (args.output / 'refresh-status.json').exists() else 'kernel-status.json' if (args.output / 'kernel-status.json').exists() else 'repair-status.json' if (args.output / 'repair-status.json').exists() else 'system-status.json')
assert json.loads(completion.read_text())['state'] == 'passed'
out = args.output / ('verification-' + datetime.now(timezone.utc).strftime('%H%M%S'))
out.mkdir()
env = dict(os.environ, PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', LC_ALL='C.UTF-8')
checks = []

def command(name, argv):
    result = subprocess.run(argv, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (out / (name + '.log')).write_text(result.stdout)
    assert result.returncode == 0, name
    return result.stdout

def check(name, passed):
    checks.append(dict(name=name, passed=bool(passed)))
    (out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
    assert passed, name

try:
    rows = command('installed', ['dpkg-query', '-W', '-f=${binary:Package}\t${Version}\t${db:Status-Status}\n'])
    installed = {}
    for line in rows.splitlines():
        name, version, status = line.split('\t')
        if status == 'installed':
            installed[name] = version
            if name.endswith(':amd64'):
                installed[name[:-6]] = version
    plan = {}
    for phase in ['edition', 'system'] + (['repair'] if (args.output / 'repair-reviewed.log').exists() else []) + (['kernel'] if (args.output / 'kernel-reviewed.log').exists() else []) + (['refresh'] if (args.output / 'refresh-reviewed.log').exists() else []):
        for line in (args.output / (phase + '-reviewed.log')).read_text().splitlines():
            match = re.match(r'^Inst (\S+)(?: \[[^\]]+\])? \((\S+)', line)
            if match:
                plan[match[1]] = match[2]
    mismatches = {name: dict(expected=version, actual=installed.get(name))
                  for name, version in plan.items() if installed.get(name) != version}
    (out / 'plan-versions.json').write_text(json.dumps(dict(packages=len(plan), mismatches=mismatches), indent=2) + '\n')
    check('reviewed installed versions', not mismatches)
    check('dpkg audit', not command('dpkg-audit', ['dpkg', '--audit']).strip())
    command('apt-check', ['apt-get', 'check'])
    check('dependency check', True)
    kernel = '7.3.0-rc6-stereo3d9'
    fallback = '7.3.0-rc6-stereo3d8'
    check('kernel image version', installed.get('linux-image-' + kernel) == '7.3.0~rc6-9.1+lc1')
    check('kernel headers version', installed.get('linux-headers-' + kernel) == '7.3.0~rc6-9.1+lc1')
    check('headers build link', (Path('/lib/modules') / kernel / 'build/Makefile').is_file())
    for version in [kernel, fallback]:
        check('image and initramfs ' + version,
              all((Path('/boot') / (prefix + version)).stat().st_size > 1024 * 1024
                  for prefix in ['vmlinuz-', 'initrd.img-']))
    initramfs = command('initramfs', ['lsinitramfs', '/boot/initrd.img-' + kernel])
    check('new modules in initramfs', ('lib/modules/' + kernel + '/') in initramfs)
    grub = Path('/boot/grub/grub.cfg').read_text()
    boot_lines = [line.strip() for line in grub.splitlines() if re.match(r'^\s*linux(?:efi)?\s', line)]
    (out / 'grub-linux-lines.json').write_text(json.dumps(boot_lines, indent=2) + '\n')
    check('new primary GRUB entry', boot_lines and ('vmlinuz-' + kernel) in boot_lines[0])
    check('retained fallback GRUB entry', any(('vmlinuz-' + fallback) in line for line in boot_lines))
    if args.hostname == cfg.get('SPARKY_A10_HOSTNAME'):
        check('A10 boot workarounds', 'rw' in boot_lines[0].split() and 'systemd.tpm2_wait=0' in boot_lines[0].split())
        expected = {'acpi-call', 'v4l2loopback', 'vhba', 'xone'}
    else:
        expected = {'acpi-call', 'hid-xpadneo', 'nvidia-fs', 'nvidia', 'r8168', 'v4l2loopback'}
    dkms = command('dkms', ['dkms', 'status', '-k', kernel])
    present = {line.split('/', 1)[0] for line in dkms.splitlines() if line.endswith(': installed')}
    check('installed DKMS modules', expected.issubset(present))
    check('no incomplete DKMS entries', all(line.endswith(': installed') for line in dkms.splitlines() if line.strip()))
    check('shader recovery marker', Path('/var/lib/dpkg-stereo/consumer-migration-glsl-v1').is_file())
    version = command('browser-version', ['/usr/lib/sparky-stereo-browser/sparky-stereo-browser', '--version'])
    check('browser executable', 'SparkyStereoBrowser 6.7.5' in version)
    for package in ['dpkg-stereo', 'sparky-stereo-browser', 'sparky-stereo-skills',
                    'linux-image-' + kernel, 'linux-headers-' + kernel]:
        command('lean-' + package, ['dpkg-stereo', '--verify', package])
    check('selected Lean Code payloads', True)
    check('online source active', 'https://repo.sparkyos.org/' in Path('/etc/apt/sources.list.d/sparky-stereo.sources').read_text())
    check('old local source retired', not Path('/etc/apt/sources.list.d/sparky-stereo-local.list').exists())
    record = dict(state='passed', hostname=args.hostname, checks=len(checks),
                  kernel=kernel, running_kernel=os.uname().release,
                  scope='Installed package, module and boot preparation; physical boot/display validation follows reboot')
except Exception as exc:
    record = dict(state='needs-review', hostname=args.hostname, error=str(exc), checks=checks)
    raise
finally:
    (out / 'status.json').write_text(json.dumps(record, indent=2) + '\n')
    print(out)
