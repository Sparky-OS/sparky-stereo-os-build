#!/bin/bash
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
# Runs only in a disposable container with the engine installed.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
exec python3 - "${1:?boot decision script}" "${2:-$HERE/share/default/sparky-stereo-vram-boost}" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

script = str(Path(sys.argv[1]).resolve())
defaults = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parent / '../share/default/sparky-stereo-vram-boost'
package = 'sparky-stereo-vram-boost'
fails = 0

def engine(*args):
    return subprocess.run(['sparky-stereo-problems', *args], text=True, capture_output=True)

def check(ok, text):
    global fails
    print(('PASS ' if ok else 'FAIL ') + text, flush=True)
    fails += not ok

with tempfile.TemporaryDirectory() as scratch:
    root = Path(scratch)
    bins = root / 'bin'
    bins.mkdir()
    sleep_log = root / 'sleep.log'
    sleeper = bins / 'sleep'
    sleeper.write_text('#!/bin/sh\necho sleep >> "$SLEEP_LOG"\n')
    sleeper.chmod(0o755)
    count = 0

    def case(label, mode, gpus=(), regions=(), controller=True, capacity=True, keys=(), on=False, reason=None, clear=True):
        global count
        count += 1
        path = root / str(count)
        path.mkdir()
        pci = path / 'pci'; pci.mkdir()
        cg = path / 'cg'; cg.mkdir()
        (cg / 'cgroup.controllers').write_text('cpu memory' + (' dmem' if controller else '') + '\n')
        if capacity:
            (cg / 'dmem.capacity').write_text(''.join(r + ' 8589934592\n' for r in regions))
        for address, driver, own in gpus:
            dev = pci / address; dev.mkdir()
            drv = path / driver; drv.mkdir(exist_ok=True)
            (dev / 'driver').symlink_to(drv)
            (dev / 'class').write_text('0x030000\n')
            if own:
                (dev / 'mem_info_vram_vendor').touch()
        config = path / 'defaults'
        config.write_text(defaults.read_text() if mode is None else 'SPARKY_STEREO_VRAM_BOOST=' + mode + '\n')
        if clear:
            assert engine('clear', '--all', package).returncode == 0
        sleep_log.unlink(missing_ok=True)
        env = dict(os.environ, SPARKY_STEREO_VRAM_BOOST_RUN=str(path / 'run'), SPARKY_STEREO_VRAM_BOOST_CGROUP=str(cg),
                   SPARKY_STEREO_VRAM_BOOST_PCI=str(pci), SPARKY_STEREO_VRAM_BOOST_DEFAULTS=str(config),
                   SPARKY_STEREO_VRAM_BOOST_WAIT='1', PATH=str(bins) + ':' + os.environ['PATH'], SLEEP_LOG=str(sleep_log))
        start = time.monotonic()
        result = subprocess.run([script], env=env, text=True, capture_output=True, timeout=3)
        elapsed = time.monotonic() - start
        records = json.loads(engine('list', '--json', package).stdout)
        state = (path / 'run/state').read_text()
        got = sorted(r['key'] for r in records)
        expected = 'on' if on else 'off'
        check(result.returncode == 0 and got == sorted(keys) and 'decision=' + expected + '\n' in state
              and (path / 'run/enabled').exists() == on and not sleep_log.exists() and elapsed < 1
              and (reason is None or reason in state),
              f'{label}: decision={expected} keys={got} exit={result.returncode} elapsed={elapsed:.4f}s sleep={sleep_log.exists()} state={state.strip()!r}')
        return records

    all_gpus = [('0000:03:00.0', 'amdgpu', False), ('0000:00:02.0', 'xe', False),
                ('0000:04:00.0', 'nouveau', False), ('0000:01:00.0', 'nvidia', False)]
    all_regions = ['drm/0000:03:00.0/vram0', 'drm/0000:00:02.0/vram0',
                   'drm/0000:04:00.0/vram', 'nvidia/00000000:01:00.0/vidmem']
    case('shipped default on all four drivers', None, all_gpus, all_regions)
    case('no controller while off', 'no', all_gpus, controller=False, capacity=False)
    case('retired auto is off', 'auto', all_gpus, all_regions)
    for gpu, region in zip(all_gpus, all_regions):
        case('yes ' + gpu[1], 'yes', [gpu], [region], on=True, reason='(' + gpu[1] + ')')
        case('missing region ' + gpu[1], 'yes', [gpu], keys=['region'])
        case('missing controller ' + gpu[1], 'yes', [gpu], controller=False, keys=['kernel'])
        case('unreadable capacity ' + gpu[1], 'yes', [gpu], capacity=False, keys=['capacity'])
    case('invalid mode', 'sometimes', all_gpus, all_regions, keys=['mode'])
    case('off clears an earlier failure', 'no', all_gpus, all_regions, clear=False)
    case('amd-dgpu', 'amd-dgpu', [('0000:03:00.0','amdgpu',True)], [all_regions[0]], on=True)
    case('amd-dgpu excludes the APU', 'amd-dgpu', [all_gpus[0]], [all_regions[0]], keys=['region'])
    case('yes with no registered GPU', 'yes', keys=['region'])
    case('one of two regions missing', 'yes', all_gpus[:2], all_regions[:1], keys=['region'], on=True)
    case('the missing region returns', 'yes', all_gpus[:2], all_regions[:2], on=True, clear=False)
    assert engine('clear', '--all', package).returncode == 0
print('failures:', fails)
sys.exit(bool(fails))
PY
