#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest-only random-phase pressure races at the cached measured allocation rate.

Uses a dedicated 2 GiB disk swap file. Temporarily stops zram to isolate the
Cushion decision. The deliberately underestimated rate must lose at least
one race. Originals are restored; no other disk swap area is disabled.
"""
import argparse
import json
import os
import random
import subprocess
import time
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('output', type=Path)
p.add_argument('--runs', type=int, default=6)
a = p.parse_args()
result = {'verified': False, 'failure': None, 'runs': []}
root = a.output.parent / 'races'
area = Path('/var/tmp/cushion-c03-race.swap')
children = []
zram = False
zram_masked = False
created = False
status = 0
guest_verified = False

def command(*words, check=True):
    r = subprocess.run(words, text=True, capture_output=True)
    if check and r.returncode:
        raise RuntimeError(f'{words}: {r.stderr}')
    return r.stdout.strip()

try:
    assert os.geteuid() == 0 and not Path('/.dockerenv').exists()
    command('systemd-detect-virt', '--vm')
    guest_verified = True
    root.mkdir(parents=True, exist_ok=True)
    cache = Path('/var/lib/cushion-swap/allocation-rate').read_text().split()
    measured, safe = int(cache[2]), int(cache[1])
    workers = min(int(cache[4]), 4)
    result['workers'] = workers
    result['rate_mib_s'] = measured
    result['safe_rate_mib_s'] = safe
    result['seed'] = 300
    random.seed(result['seed'])
    assert not area.exists(), 'dedicated scratch swap already exists'
    command('systemctl', 'stop', 'cushion-swap')
    zram = command('systemctl', 'is-active', 'dev-zram0.swap', check=False) == 'active'
    if zram:
        command('systemctl', 'stop', 'dev-zram0.swap')
    command('systemctl', 'mask', '--runtime', 'dev-zram0.swap')
    zram_masked = True
    assert len(Path('/proc/swaps').read_text().splitlines()) == 1, 'another active swap would mask the control'
    command('fallocate', '-l', '2G', str(area))
    created = True
    area.chmod(0o600)
    command('mkswap', str(area))
    assert Path('/proc/sys/vm/swappiness').read_text().strip() == '1', 'requires edition swappiness 1'
    for label, assumption, count in [('calibrated', safe, a.runs), ('underestimated', 1, 2)]:
        for i in range(count):
            directory = root / f'{label}-{i}'
            directory.mkdir()
            command('swapoff', str(area), check=False)
            env = os.environ | {'CUSHION_SWAP_CONFIG': '/nonexistent', 'CUSHION_SWAP_AREA': str(area),
                'STATE_DIR': str(directory / 'state'), 'PSI': 'off', 'MAX_ALLOC_MIB_S': str(assumption),
                'LOG_EVERY_CYCLE': 'yes'}
            log = (directory / 'daemon.log').open('w')
            daemon = subprocess.Popen(['/usr/sbin/cushion-swap'], env=env, stdout=log, stderr=log)
            children.append(daemon)
            Path(f'/proc/{daemon.pid}/oom_score_adj').write_text('-1000')
            jitter = random.uniform(0.05, 3)
            time.sleep(jitter)
            fields = dict(line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())
            available = int(fields['MemAvailable'].split()[0]) // 1024
            grow_logs, growers = [], []
            started = time.monotonic()
            for worker in range(workers):
                handle = (directory / f'grow-{worker}.log').open('w')
                grow_logs.append(handle)
                child = subprocess.Popen(['python3', str(Path(__file__).parent / 'guest/memgrow.py'),
                    str(measured / workers), str((available + 512 + workers - 1) // workers), '2'],
                    stdout=handle, stderr=handle, env=os.environ | {"CUSHION_BASE_PAGES": "yes"})
                children.append(child)
                growers.append(child)
            codes = [child.wait(timeout=max(1, 90 - (time.monotonic()-started))) for child in growers]
            elapsed = time.monotonic() - started
            for handle in grow_logs:
                handle.close()
            time.sleep(0.1)
            daemon.terminate()
            daemon.wait(timeout=5)
            log.close()
            deploy = 'DEPLOY succeeded' in (directory / 'daemon.log').read_text()
            kernel = command('dmesg')
            oom = any(code == -9 and f'Killed process {child.pid} ' in kernel
                for code, child in zip(codes, growers))
            entry = {'case': label, 'run': i, 'jitter_s': jitter, 'rate_mib_s': measured,
                'assumed_rate_mib_s': assumption, 'target_mib': available+512,
                'grow_status': codes, 'grow_pids': [child.pid for child in growers],
                'oom_kill_confirmed': oom, 'deployed': deploy, 'seconds': elapsed,
                'grow_output': [(directory / f'grow-{worker}.log').read_text() for worker in range(workers)],
                'completed': all(code == 0 for code in codes) and all('released' in
                    (directory / f'grow-{worker}.log').read_text() for worker in range(workers))}
            result['runs'].append(entry)
            command('swapoff', str(area), check=False)
            if label == 'calibrated' and not (entry['completed'] and deploy):
                raise AssertionError(f'calibrated race lost: {entry}')
    bad = [row for row in result['runs'] if row['case'] == 'underestimated']
    assert any(row['oom_kill_confirmed'] for row in bad), 'underestimated-rate control did not lose'
    result['verified'] = True
except Exception as error:
    result['failure'] = str(error)
    status = 1
finally:
    for child in children:
        if child.poll() is None:
            child.kill()
            child.wait()
    if created:
        command('swapoff', str(area), check=False)
        if not any(str(area) in line for line in Path('/proc/swaps').read_text().splitlines()[1:]):
            area.unlink()
        else:
            result['failure'] = 'scratch swap could not be switched off during cleanup'
            status = 1
    if zram_masked:
        command('systemctl', 'unmask', '--runtime', 'dev-zram0.swap', check=False)
    if zram:
        command('systemctl', 'start', 'dev-zram0.swap', check=False)
    if guest_verified:
        command('systemctl', 'start', 'cushion-swap', check=False)
a.output.write_text(json.dumps(result, indent=2)+'\n')
raise SystemExit(status)
