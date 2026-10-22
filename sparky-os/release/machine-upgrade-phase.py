#!/usr/bin/env python3
"""Run one reviewed, zero-removal upgrade phase; never reboot or select new work."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import socket
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('output', type=Path)
p.add_argument('phase', choices=['compatibility', 'edition', 'system', 'repair', 'kernel', 'refresh'])
p.add_argument('--package-archive', type=Path, action='append', default=[])
p.add_argument('--hostname', required=True)
p.add_argument('--reviewed-simulation', type=Path, required=True)
args = p.parse_args()
assert os.geteuid() == 0
assert socket.gethostname() == args.hostname
args.output.mkdir(parents=True, exist_ok=True)
state = args.output / (args.phase + '-status.json')
assert not state.exists(), 'Retain the earlier phase; use a fresh output directory for retries'
env = dict(os.environ, PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
           DEBIAN_FRONTEND='noninteractive', APT_LISTCHANGES_FRONTEND='none',
           NEEDRESTART_MODE='l')
actions = {
    'compatibility': ['install', 'sparky-stereo-dkms-compat'],
    'edition': ['install', 'dpkg-stereo', 'sparky-stereo-apt',
                'sparky-stereo-skills', 'sparky-stereo-browser'],
    'system': ['dist-upgrade'],
    'refresh': ['dist-upgrade'],
}
if args.phase in ['repair', 'kernel']:
    assert args.package_archive and all(path.is_file() for path in args.package_archive)
    actions[args.phase] = (['-f'] if args.phase == 'repair' else []) + ['install', *[str(path.resolve()) for path in args.package_archive]]
else:
    assert not args.package_archive
command = ['apt-get', '--no-remove', '-o', 'Dpkg::Use-Pty=0',
           '-o', 'Dpkg::Options::=--force-confdef',
           '-o', 'Dpkg::Options::=--force-confold']
record = dict(phase=args.phase, hostname=args.hostname, state='checking',
              started_utc=datetime.now(timezone.utc).isoformat(),
              scope='Previously reviewed zero-removal package transaction; no reboot',
              reviewed_simulation=str(args.reviewed_simulation))

def save():
    temp = state.with_suffix('.tmp')
    temp.write_text(json.dumps(record, indent=2) + '\n')
    temp.replace(state)

def operations(text):
    lines = text.splitlines()
    assert not any(line.startswith('Remv ') for line in lines), 'Removal proposed'
    return sorted(line for line in lines if line.startswith('Inst '))

save()
try:
    expected = operations(args.reviewed_simulation.read_text())
    probe = subprocess.run(command + ['-s'] + actions[args.phase], env=env,
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (args.output / (args.phase + '-recheck.log')).write_text(probe.stdout)
    assert probe.returncode == 0, 'Immediate simulation failed'
    assert operations(probe.stdout) == expected, 'APT plan changed since review'
    record.update(state='running', installations=len(expected), command=command + ['-y'] + actions[args.phase])
    save()
    with (args.output / (args.phase + '-install.log')).open('x') as log:
        result = subprocess.run(record['command'], env=env, stdout=log, stderr=subprocess.STDOUT)
    record['exit_code'] = result.returncode
    assert result.returncode == 0, 'Package transaction failed; inspect retained log'
    audit = subprocess.run(['dpkg', '--audit'], env=env, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (args.output / (args.phase + '-dpkg-audit.log')).write_text(audit.stdout)
    assert audit.returncode == 0 and not audit.stdout.strip(), 'dpkg audit is not clean'
    with (args.output / (args.phase + '-apt-check.log')).open('x') as log:
        check = subprocess.run(['apt-get', 'check'], env=env, stdout=log, stderr=subprocess.STDOUT)
    assert check.returncode == 0, 'APT dependency check failed'
    record['state'] = 'passed'
except Exception as exc:
    record.update(state='needs-repair', error=str(exc))
    raise
finally:
    record['updated_utc'] = datetime.now(timezone.utc).isoformat()
    save()
