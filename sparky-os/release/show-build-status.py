#!/usr/bin/env python3
"""Read only bounded log tails while long native builds run."""
from datetime import datetime
import json
from pathlib import Path
import re
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

base = cfg.path('SPARKY_MIGRATION_WORK')
print(datetime.now().astimezone().isoformat(timespec='seconds'))
for name in ['sparky-stereo-browser-amd64', 'mesa-i386', 'abseil-amd64',
             'abseil-i386', 'qemu-amd64', 'linux-stereo-base-amd64', 'linux-stereo-v3-amd64',
             'linux-stereo-rt-amd64']:
    job = base / 'jobs' / name
    if not job.exists():
        continue
    status = job / 'status.json'
    state = json.loads(status.read_text())['state'] if status.exists() else 'running'
    log = job / ('resume-cargo.log' if name.startswith('sparky-stereo-browser') else 'build.log')
    with log.open('rb') as stream:
        stream.seek(max(0, log.stat().st_size - 16384))
        lines = stream.read().decode(errors='replace').splitlines()
    markers = [line for line in lines if re.match(r'^\[\s*\d+(?:%|/)|^\d+:\d|^.*tests passed|^lc1:', line)]
    print(name, state, (markers or lines or [''])[ -1][:160])
runtime = base / 'browser-installed-check'
if (runtime / 'results-summary.json').exists():
    rows = json.loads((runtime / 'results-summary.json').read_text())
    status = json.loads((runtime / 'status.json').read_text())
    print('Browser runtime:', sum(row['passed'] for row in rows), '/ 77 passed;', status['state'])
for flavour in ['base', 'v3', 'rt']:
    for filename in ['status.json', 'dkms-status.json']:
        report = base / 'kernel-qualification' / flavour / filename
        if report.exists():
            print('Kernel qualification:', flavour, filename, json.loads(report.read_text())['state'])
print('Root free GiB:', round(shutil.disk_usage(base).free / 1024**3, 1))
