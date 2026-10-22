#!/usr/bin/env python3
"""Queue isolated checks after each completed kernel; never publish or install."""
from pathlib import Path
from datetime import datetime, timezone
import json
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
out = base / 'kernel-qualification-queue'
out.mkdir(exist_ok=True)


def read_status(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}  # Some producers truncate then write; retry the next poll.


def save(state, **details):
    value = dict(state=state, updated_utc=datetime.now(timezone.utc).isoformat(), **details)
    temporary = out / 'status.tmp'
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(out / 'status.json')


try:
    for flavour in ['base', 'v3', 'rt']:
        job = base / 'jobs' / ('linux-stereo-' + flavour + '-amd64')
        save('waiting', flavour=flavour)
        while True:
            status = read_status(job / 'status.json')
            if status.get('state') == 'needs-repair':
                raise RuntimeError(flavour + ': kernel build needs repair; qualification not started')
            qemu = read_status(base / 'qemu-installed-check/status.json')
            if qemu.get('passed') is False:
                raise RuntimeError('Installed QEMU check needs repair')
            ready = status.get('state') == 'candidate-needs-review' and qemu.get('passed') is True
            if ready and shutil.disk_usage(base).free >= 20 * 1024**3:
                break
            time.sleep(15)
        for script in ['qualify-kernel-boot.py', 'qualify-kernel-dkms.py']:
            save('running', flavour=flavour, script=script)
            subprocess.run([sys.executable, str(Path(__file__).resolve().parent / script), flavour], check=True)
        print(flavour, 'isolated boot and DKMS checks passed; release review remains', flush=True)
    save('passed', scope='All three new kernels completed isolated boot and DKMS checks')
except BaseException as error:
    save('needs-repair', error=str(error))
    raise
