#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare old and calibrated pacing in the isolated guest; no swap is changed."""
import argparse
import json
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('old_daemon', type=Path)
parser.add_argument('--seconds', type=int, default=40)
args = parser.parse_args()
result = {'verified': False, 'failure': None, 'runs': []}
status = 0
guest_verified = False
try:
    assert os.geteuid() == 0 and not Path('/.dockerenv').exists()
    subprocess.run(['systemd-detect-virt', '--vm'], check=True, capture_output=True)
    guest_verified = True
    cache = Path('/var/lib/cushion-swap/allocation-rate').read_text().split()
    result['calibration'] = cache
    assert len(cache) == 6 and int(cache[1]) >= int(cache[2]) * 2
    subprocess.run(['systemctl', 'stop', 'cushion-swap'], check=True)
    for label, daemon in [('before', args.old_daemon), ('after', Path('/usr/sbin/cushion-swap'))]:
        with tempfile.TemporaryDirectory(prefix='cushion-pacing-') as scratch:
            env = os.environ | {'CUSHION_SWAP_CONFIG': '/nonexistent', 'FSTAB_PATH': '/nonexistent',
                'CUSHION_SWAP_AREA': '', 'STATE_DIR': scratch, 'LOG_EVERY_CYCLE': 'yes', 'PSI': 'off'}
            path = Path(scratch) / 'log'
            with path.open('w') as log:
                child = subprocess.Popen(['bash', str(daemon)], env=env, stdout=log, stderr=log)
                try:
                    time.sleep(1)
                    def cpu():
                        values = Path(f'/proc/{child.pid}/stat').read_text().split(') ', 1)[1].split()
                        return sum(int(values[i]) for i in (11, 12))
                    cpu0 = cpu()
                    data0, size0 = path.read_text(), path.stat().st_size
                    n0 = len(re.findall(r'sample: .*cycle=', data0))
                    time.sleep(args.seconds)
                    cpu1 = cpu()
                    data1, size1 = path.read_text(), path.stat().st_size
                    n1 = len(re.findall(r'sample: .*cycle=', data1))
                    state = dict(line.split('=', 1) for line in (Path(scratch) / 'status').read_text().splitlines())
                    count = n1 - n0
                    assert child.poll() is None and count > 0
                    result['runs'].append({'label': label, 'seconds': args.seconds, 'cycles': count,
                        'interval_s': args.seconds / count,
                        'cpu_percent_core': (cpu1-cpu0) / os.sysconf('SC_CLK_TCK') / args.seconds * 100,
                        'bytes_per_cycle': (size1-size0) / count,
                        'weekly_cycle_log_bytes': (size1-size0) / args.seconds * 604800, 'state': state})
                finally:
                    child.terminate()
                    child.wait(timeout=5)
    assert result['runs'][1]['state']['CALIBRATED'] == 'yes'
    assert int(result['runs'][1]['state']['MAX_ALLOC_MIB_S']) == int(cache[1])
    result['verified'] = True
except Exception as error:
    result['failure'] = str(error)
    status = 1
finally:
    if guest_verified:
        subprocess.run(['systemctl', 'start', 'cushion-swap'], check=False)
args.output.write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(status)
