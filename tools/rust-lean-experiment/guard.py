#!/usr/bin/env python3
"""Run a named container with bounded disk/CPU-temperature monitoring."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.partial')
    with tmp.open('w') as f:
        json.dump(value, f, indent=2, sort_keys=True)
        f.write('\n'); f.flush(); os.fsync(f.fileno())
    tmp.replace(path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def machine(sysroot=Path('/sys'), require_temperature=True):
    temperatures = {}
    for p in (sysroot/'class/hwmon').glob('hwmon*'):
        try:
            name = (p/'name').read_text().strip()
        except OSError:
            continue
        if name not in ('k10temp', 'coretemp', 'zenpower'):
            continue
        for t in p.glob('temp*_input'):
            label = t.with_name(t.name.replace('_input', '_label'))
            key = name+':'+(label.read_text().strip() if label.exists() else t.stem)
            temperatures[key] = int(t.read_text())/1000
            if not 0 < temperatures[key] < 125:
                raise RuntimeError('invalid CPU temperature: '+key)
    if require_temperature and not temperatures:
        raise RuntimeError('CPU temperature unavailable: expected a readable k10temp/coretemp sensor')
    frequencies, governors = {}, {}
    for p in (sysroot/'devices/system/cpu').glob('cpu[0-9]*/cpufreq'):
        if (p/'scaling_cur_freq').exists():
            frequencies[p.parent.name] = int((p/'scaling_cur_freq').read_text())
        if (p/'scaling_governor').exists():
            governors[p.parent.name] = (p/'scaling_governor').read_text().strip()
    if not frequencies or not governors:
        raise RuntimeError('CPU frequency or governor unavailable')
    return {'unix': time.time(), 'temperatures_c': temperatures, 'frequency_khz': frequencies,
            'governor': governors, 'load': list(os.getloadavg()), 'kernel': os.uname().release,
            'max_temperature_c': max(temperatures.values()) if temperatures else None}


def guarded(config):
    name = config['name']
    if not name.startswith('rl541-') or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in name):
        raise ValueError('container name must be a safe rl541 name')
    output = Path(config['output']); output.mkdir(parents=True, exist_ok=True)
    engine = config['engine']
    interval = float(config.get('interval', 5))
    paused, paused_at, paused_seconds = False, None, 0.0
    proc = None
    before = machine(Path(config.get('sysroot', '/sys')))

    def control(action):
        return subprocess.run([*engine, action, name], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    def sample():
        now = machine(Path(config.get('sysroot', '/sys')))
        now['free_bytes'] = {p: shutil.disk_usage(p).free for p in config['floors_gib']}
        now['paused'] = paused
        for p, floor in config['floors_gib'].items():
            if now['free_bytes'][p] < (floor+5)*1024**3:
                raise RuntimeError(f'space guard: {p} has {now["free_bytes"][p]} bytes; floor plus 5 GiB crossed')
        return now

    previous_handlers = {}

    def interrupted(signum, frame):
        raise RuntimeError(f'worker interrupted by signal {signum}; the unfinished step is not accepted')

    for sig in (signal.SIGTERM, signal.SIGINT):
        previous_handlers[sig] = signal.signal(sig, interrupted)
    try:
        cooldown_started = time.monotonic()
        deadline = cooldown_started+float(config.get('cooldown_timeout_seconds', 7200))
        with (output/'telemetry.jsonl').open('w') as telemetry:
            while True:
                now = sample(); telemetry.write(json.dumps(now)+'\n'); telemetry.flush()
                if now['max_temperature_c'] <= config.get('start_temperature_c', 62):
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError('cool-down timeout before starting the container')
                time.sleep(interval)
            started = now
            cooldown_seconds = time.monotonic()-cooldown_started
            with (output/'container.log').open('wb') as log:
                proc = subprocess.Popen(config['argv'], stdout=log, stderr=subprocess.STDOUT,
                                        env=dict(os.environ, LC_ALL='C'))
                while proc.poll() is None:
                    now = sample(); telemetry.write(json.dumps(now)+'\n'); telemetry.flush()
                    temperature = now['max_temperature_c']
                    if temperature > config.get('stop_temperature_c', 90) and not paused:
                        if control('pause').returncode:
                            raise RuntimeError('could not pause the hot container')
                        paused, paused_at = True, time.monotonic()
                    elif paused and time.monotonic()-paused_at > float(config.get('cooldown_timeout_seconds',7200)):
                        raise RuntimeError('cool-down timeout while thermally paused')
                    elif paused and temperature <= config.get('start_temperature_c', 62):
                        if control('unpause').returncode:
                            raise RuntimeError('could not resume the cooled container')
                        paused_seconds += time.monotonic()-paused_at
                        paused = False
                    try:
                        proc.wait(timeout=interval)
                    except subprocess.TimeoutExpired:
                        pass
                if proc.returncode:
                    raise RuntimeError(f'container exited {proc.returncode}; see {output}/container.log')
            after = sample(); telemetry.write(json.dumps(after)+'\n')
        result = {'complete': True, 'before_cooldown': before, 'before': started, 'after': after,
                  'cooldown_seconds': cooldown_seconds, 'thermal_paused_seconds': paused_seconds}
        atomic(output/'guard-result.json', result)
        return result
    except BaseException as error:
        if proc is not None:
            if paused:
                control('unpause')
            control('kill')
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
        atomic(output/'failed.json', {'complete': False, 'error': str(error), 'before': before})
        raise
    finally:
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    import sys
    guarded(json.loads(Path(sys.argv[1]).read_text()))
