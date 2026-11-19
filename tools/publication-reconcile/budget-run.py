#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run one named container task while enforcing lane disk budgets."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import time

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--scratch', type=Path, required=True)
ap.add_argument('--scratch-gib', type=float, required=True)
ap.add_argument('--root-min-free-gib', type=float, default=1)
ap.add_argument('--build-min-free-gib', type=float, default=2)
ap.add_argument('--container', required=True)
ap.add_argument('--log', type=Path, required=True)
ap.add_argument('--metrics', type=Path, help='JSONL sampled usage, free space and measured scratch peak')
def positive_seconds(value):
    number = float(value)
    if not 0 < number < float('inf'):
        raise argparse.ArgumentTypeError('sampling interval must be positive')
    return number
ap.add_argument('--interval-seconds', type=positive_seconds, default=5)
ap.add_argument('command', nargs=argparse.REMAINDER)
a = ap.parse_args()
command = a.command[1:] if a.command[:1] == ['--'] else a.command
peak = 0
if a.metrics:
    a.metrics.write_text('')
def observe(event):
    global peak
    measurement = subprocess.run(['du', '-sx', '--block-size=1', str(a.scratch)], capture_output=True, text=True)
    if measurement.returncode:
        raise OSError('scratch measurement failed: ' + measurement.stderr.strip())
    used = int(measurement.stdout.split()[0])
    free_root = shutil.disk_usage('/').free
    free_build = shutil.disk_usage('/mnt/build').free
    peak = max(peak, used)
    if a.metrics:
        with a.metrics.open('a') as stream:
            stream.write(json.dumps(dict(time_utc=datetime.now(timezone.utc).isoformat(), event=event,
                                        scratch_bytes=used, peak_scratch_bytes=peak,
                                        root_free_bytes=free_root, build_free_bytes=free_build)) + '\n')
    return used, free_root, free_build
with a.log.open('w') as log:
    child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    while child.poll() is None:
        try:
            used, free_root, free_build = observe('running')
        except (OSError, ValueError, IndexError) as error:
            print('BUDGET STOP: ' + str(error), flush=True)
            subprocess.run(['docker', 'stop', '--timeout', '5', a.container], check=False)
            child.wait(timeout=30)
            raise SystemExit(3)
        if used > a.scratch_gib * 1024**3 or free_root < a.root_min_free_gib * 1024**3 or free_build < a.build_min_free_gib * 1024**3:
            print(f'BUDGET STOP scratch={used}, root-free={free_root}, build-free={free_build}', flush=True)
            subprocess.run(['docker', 'stop', '--timeout', '5', a.container], check=False)
            child.wait(timeout=30)
            raise SystemExit(3)
        time.sleep(a.interval_seconds)
    try:
        observe('finished')
    except (OSError, ValueError, IndexError) as error:
        print('BUDGET STOP: ' + str(error), flush=True)
        raise SystemExit(3)
    raise SystemExit(child.returncode)
