#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run one named container task while enforcing lane disk budgets."""
import argparse
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
ap.add_argument('command', nargs=argparse.REMAINDER)
a = ap.parse_args()
command = a.command[1:] if a.command[:1] == ['--'] else a.command
with a.log.open('w') as log:
    child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    while child.poll() is None:
        measurement = subprocess.run(['du', '-sx', '--block-size=1', str(a.scratch)], capture_output=True, text=True)
        if measurement.returncode:
            print('BUDGET STOP: scratch measurement failed: ' + measurement.stderr.strip(), flush=True)
            subprocess.run(['docker', 'stop', '--timeout', '5', a.container], check=False)
            child.wait(timeout=30)
            raise SystemExit(3)
        used = int(measurement.stdout.split()[0])
        free_root = shutil.disk_usage('/').free
        free_build = shutil.disk_usage('/mnt/build').free
        if used > a.scratch_gib * 1024**3 or free_root < a.root_min_free_gib * 1024**3 or free_build < a.build_min_free_gib * 1024**3:
            print(f'BUDGET STOP scratch={used}, root-free={free_root}, build-free={free_build}', flush=True)
            subprocess.run(['docker', 'stop', '--time', '5', a.container], check=False)
            child.wait(timeout=30)
            raise SystemExit(3)
        time.sleep(5)
    raise SystemExit(child.returncode)
