#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest-only weekly rotation proof, temporarily enabling cycle logging.

JSON is the first argument. Restores the settings file and service on exit.
Forced rotations exercise copytruncate; an unforced repeat must not rotate.
rotate 1 with delaycompress retains .1 uncompressed, never a .2.gz.
"""
import argparse
import json
import os
import re
import stat
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
result = {'verified': False, 'failure': None}
settings = Path('/etc/default/cushion-swap')
log = Path('/var/log/cushion-swap/cushion-swap.log')
conf = Path('/etc/logrotate.d/sparky-stereo-cushion-swap')
original = None
status = 0

def command(*words):
    return subprocess.run(words, capture_output=True, text=True, check=True).stdout.strip()

def cycles(text):
    return [int(n) for n in re.findall(r'sample: .*cycle=(\d+)', text)]

try:
    assert os.geteuid() == 0 and not Path('/.dockerenv').exists()
    command('systemd-detect-virt', '--vm')
    policy = conf.read_text().split()
    assert 'weekly' in policy and policy[policy.index('rotate')+1] == '1'
    assert not any(word in policy for word in ('daily','hourly','maxsize','size'))
    original = settings.read_bytes()
    text = original.decode()
    settings.write_text('\n'.join(line for line in text.splitlines()
        if not line.startswith(('LOG_EVERY_CYCLE=', 'PSI=', 'PACING=', 'POLL_INTERVAL_SEC='))) +
        '\nLOG_EVERY_CYCLE=yes\nPSI=off\nPACING=fixed\nPOLL_INTERVAL_SEC=0.05\n')
    command('systemctl', 'restart', 'cushion-swap')
    time.sleep(1)
    sizes = [log.stat().st_size]
    time.sleep(2)
    sizes.append(log.stat().st_size)
    assert sizes[1] > sizes[0], 'opt-in log did not grow'
    result['growing_bytes'] = sizes
    every = []
    rotations = []
    state = args.output.with_suffix('.logrotate-state')
    for number in range(3):
        started = time.monotonic()
        command('logrotate','-f','-s',str(state),str(conf))
        duration = time.monotonic()-started
        archive = log.with_name(log.name+'.1')
        every.extend(cycles(archive.read_text()))
        rotations.append({'seconds':duration,'archive_bytes':archive.stat().st_size})
        assert not log.with_name(log.name+'.2.gz').exists(), 'extra archive retained'
        time.sleep(1)
    every.extend(cycles(log.read_text()))
    gaps = [(a,b) for a,b in zip(every,every[1:]) if b != a+1]
    assert all(b>a for a,b in gaps), 'cycle numbering reversed'
    result['continuity'] = {'cycles':len(every),'gaps':gaps,
        'lost_cycles':sum(b-a-1 for a,b in gaps)}
    before = log.with_name(log.name+'.1').read_bytes()
    command('logrotate','-s',str(state),str(conf))
    assert before == log.with_name(log.name+'.1').read_bytes(), 'early unforced rotation'
    result['rotations'] = rotations
    result['unforced_repeat_rotated'] = False
    for path, mode in [(log.parent,0o750),(log,0o640)]:
        assert stat.S_IMODE(path.stat().st_mode) == mode
        assert command('stat','-c','%U:%G',str(path)) == 'root:adm'
    result['verified'] = True
except Exception as error:
    result['failure'] = str(error)
    status = 1
finally:
    if original is not None:
        settings.write_bytes(original)
        command('systemctl','restart','cushion-swap')
args.output.write_text(json.dumps(result, indent=2)+'\n')
os.sync()
raise SystemExit(status)
