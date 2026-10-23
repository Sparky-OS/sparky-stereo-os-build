#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""A10 package bench, launched by the main session; dry run is the default."""
import argparse
import csv
import json
import os
from pathlib import Path
import re
import shlex
import signal
import shutil
import socket
import subprocess
import sys
import threading
import time

MODES = {
    'E2': ('eDP-1', '1366x768@60.01'),
    'E3': ('eDP-1', '1366x768@60.01(virtual-3D:5)'),
    'T2': ('HDMI-A-1', '1920x1080@30.00'),
    'T3': ('HDMI-A-1', '1920x1080@30.00(3D-FP)'),
}
SETUPS = [
    ('laptop-2d', 'E2', None), ('laptop-3d', 'E3', None),
    ('tv-2d', None, 'T2'), ('tv-3d', None, 'T3'),
    ('extended-2d-2d', 'E2', 'T2'), ('extended-3d-2d', 'E3', 'T2'),
    ('extended-2d-3d', 'E2', 'T3'), ('extended-3d-3d', 'E3', 'T3'),
]
ROUTES = ('integrated', 'prime-discrete', 'default')
APIS = ('vulkan', 'opengl')
FILMS = ('2d', '3d', 'coyote')


def cases(pattern='.*'):
    for setup, edp, tv in SETUPS:
        for output in [o for o, present in [('eDP-1', edp), ('HDMI-A-1', tv)] if present]:
            for api in APIS:
                for route in ROUTES:
                    for film in FILMS:
                        name = '/'.join((setup, output, api, route, film))
                        if re.search(pattern, name):
                            yield dict(name=name, setup=setup, edp=edp, tv=tv,
                                       output=output, api=api, route=route, film=film)


def mode_ids(text):
    result = {}
    output = None
    for line in re.sub(r'\x1b\[[0-9;]*m', '', text).splitlines():
        m = re.search(r'Output:\s+\d+\s+(\S+)', line)
        if m:
            output = m[1]
        if 'Modes:' in line:
            for token in line.split('Modes:', 1)[1].split():
                token = token.rstrip('*!')
                if ':' in token:
                    ident, label = token.split(':', 1)
                    for key, expected in MODES.items():
                        if (output, label) == expected:
                            result[key] = ident
    if set(result) != set(MODES):
        raise ValueError(f'Missing exact measured display modes: {set(MODES)-set(result)}')
    return result


def restore_args(snapshot):
    args = []
    for output in snapshot['outputs']:
        name = output['name']
        args.append(f'output.{name}.{"enable" if output["enabled"] else "disable"}')
        if output['enabled']:
            args.append(f'output.{name}.mode.{output["currentModeId"]}')
            pos = output['pos']
            args += [f'output.{name}.position.{pos["x"]},{pos["y"]}',
                     f'output.{name}.scale.{output["scale"]}']
            if output.get('replicationSource', 0):
                source = next(o['name'] for o in snapshot['outputs'] if o['id'] == output['replicationSource'])
                args.append(f'output.{name}.mirror.{source}')
            else:
                args.append(f'output.{name}.mirror.none')
    return args


def run(*args, **kw):
    return subprocess.run(args, check=True, text=True, **kw)


def mark(root, name):
    with (root/'marks.csv').open('a') as stream:
        csv.writer(stream).writerow((name, f'{time.monotonic():.6f}'))


def read(path):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return ''


def machine_logger(root, stop):
    def cpu():
        values = [int(v) for v in read('/proc/stat').splitlines()[0].split()[1:9]]
        return sum(values), values[3]+values[4]
    total, idle = cpu()
    cards = sorted(Path('/sys/class/drm').glob('card[0-9]'))
    sensors = sorted(Path('/sys/class/hwmon').glob('hwmon*'))
    with (root/'sys.csv').open('w') as stream:
        writer = csv.writer(stream)
        writer.writerow(['uptime', 'cpu_busy', 'cpu_mhz'] + [f'gpu_busy_{c.name}' for c in cards] + ['sensors_json'])
        while not stop.wait(1):
            new_total, new_idle = cpu()
            busy = 100*((new_total-total)-(new_idle-idle))/max(1, new_total-total)
            total, idle = new_total, new_idle
            frequencies = [float(read(p)) for p in Path('/sys/devices/system/cpu').glob('cpu*/cpufreq/scaling_cur_freq') if read(p)]
            measured = {}
            for sensor in sensors:
                for value in list(sensor.glob('temp*_input'))+list(sensor.glob('power*_input'))+list(sensor.glob('power*_average')):
                    measured[f'{read(sensor/"name")}/{value.name}'] = read(value)
            writer.writerow([f'{time.monotonic():.6f}', f'{busy:.3f}', sum(frequencies)/len(frequencies)/1000 if frequencies else ''] + [read(c/'device/gpu_busy_percent') for c in cards] + [json.dumps(measured, sort_keys=True)])
            stream.flush()


def gpu_pci():
    devices = {}
    for card in sorted(Path('/sys/class/drm').glob('card[0-9]')):
        connected = any(read(p/'status') == 'connected' for p in card.parent.glob(card.name+'-*'))
        pci = (card/'device').resolve().name
        if read(card/'device/vendor') != '0x1002' or not re.fullmatch(r'[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]', pci):
            continue
        key = 'integrated' if connected else 'discrete'
        if key in devices:
            raise ValueError('Ambiguous AMD display topology')
        devices[key] = 'pci-'+pci.replace(':', '_').replace('.', '_')
    if set(devices) != {'integrated', 'discrete'}:
        raise ValueError('Expected the A10 AMD display GPU and connectorless discrete GPU')
    return devices


def counters(path):
    result = {}
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(.3)
            client.connect(str(path))
            for i, prop in enumerate(('hwdec-current', 'decoder-frame-drop-count', 'frame-drop-count', 'vo-delayed-frame-count', 'video-params', 'video-out-params')):
                client.sendall((json.dumps({'command': ['get_property', prop], 'request_id': i})+'\n').encode())
            data = b''
            while len(result) < 6:
                chunk = client.recv(65536)
                if not chunk:
                    break
                data += chunk
                while b'\n' in data:
                    line, data = data.split(b'\n', 1)
                    reply = json.loads(line)
                    if 'request_id' in reply:
                        result[str(reply['request_id'])] = reply
    except (OSError, ValueError):
        pass
    return result


def execute(a):
    # This script is never a host benchmark by accident.
    model = ' '.join(read('/sys/class/dmi/id/'+field) for field in ('product_name', 'product_version', 'product_family'))
    if '310-15ABR' not in model or 'A10' not in read('/proc/cpuinfo'):
        raise ValueError('Execution requires the granted A10 laptop, not this host')
    for command in ('kscreen-doctor', 'mpv', 'ffprobe', 'qdbus6', 'dpkg-query'):
        if not shutil.which(command):
            raise ValueError(f'Missing installed command: {command}')
    expected = json.loads(a.versions.read_text())[a.phase]
    actual = {}
    for package, version in expected.items():
        installed = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', package], text=True)
        if installed != version:
            raise ValueError(f'{package}: expected {version}, installed {installed}')
        actual[package] = installed
    films = {'2d': a.film_2d, '3d': a.film_3d, 'coyote': a.coyote}
    for path in films.values():
        if not path.is_file():
            raise ValueError(f'Missing recorded film: {path}')
    root = a.output.resolve()/a.phase
    root.mkdir(parents=True, exist_ok=False)
    (root/'packages.json').write_text(json.dumps(actual, indent=2)+'\n')
    for name, path in films.items():
        with (root/(name+'-source.json')).open('w') as stream:
            run('ffprobe', '-v', 'error', '-select_streams', 'v:0', '-read_intervals', '%+#8',
                '-show_streams', '-show_frames', '-of', 'json', str(path), stdout=stream)
    snapshot = json.loads(subprocess.check_output(['kscreen-doctor', '-j'], text=True))
    restore = restore_args(snapshot)
    (root/'outputs-original.json').write_text(json.dumps(snapshot, indent=2)+'\n')
    ids = mode_ids(subprocess.check_output(['kscreen-doctor', '-o'], text=True))
    devices = gpu_pci()
    (root/'gpu-topology.json').write_text(json.dumps(devices, indent=2)+'\n')
    kwin_files = [a.kwin_log_dir/f'kwin perf statistics {out}.csv' for out in ('eDP-1', 'HDMI-A-1')]
    if not all(p.is_file() for p in kwin_files):
        raise ValueError('Enable KWin KWIN_LOG_PERFORMANCE_DATA=1 in the bench session first and supply its working directory')
    for p in kwin_files:
        header = p.open().readline()
        if 'pageflip timestamp' not in header or 'render start' not in header:
            raise ValueError(f'Unexpected per-frame log: {p}')
    def interrupted(signum, frame):
        raise KeyboardInterrupt(f'Interrupted by signal {signum}')
    previous_term = signal.signal(signal.SIGTERM, interrupted)
    stop = threading.Event()
    logger = threading.Thread(target=machine_logger, args=(root, stop))
    logger.start()
    player = None
    script_id = None
    setup = None
    try:
        for case in cases(a.select):
            if case['setup'] != setup:
                setup = case['setup']
                args = []
                for out, key in [('eDP-1', case['edp']), ('HDMI-A-1', case['tv'])]:
                    args.append(f'output.{out}.{"enable" if key else "disable"}')
                    if key:
                        args += [f'output.{out}.mode.{ids[key]}', f'output.{out}.mirror.none',
                                 f'output.{out}.position.{"0,0" if out == "eDP-1" or not case["edp"] else "1366,0"}']
                run('kscreen-doctor', *args, stdout=(root/'doctor.log').open('a'), stderr=subprocess.STDOUT)
                time.sleep(7)
                time.sleep(30)
                mark(root, setup+'/idle')
                time.sleep(120)
                mark(root, setup+'/idle-end')
            name = case['name'].replace('/', '-')
            ipc = root/(name+'.sock')
            env = os.environ.copy()
            for key in ('DRI_PRIME', 'MESA_VK_DEVICE_SELECT', 'MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE', '__EGL_VENDOR_LIBRARY_FILENAMES', 'VK_ICD_FILENAMES', 'VK_DRIVER_FILES'):
                env.pop(key, None)
            if case['route'] == 'integrated':
                env['DRI_PRIME'] = devices['integrated']+('!' if case['api'] == 'vulkan' else '')
            elif case['route'] == 'prime-discrete':
                env['DRI_PRIME'] = devices['discrete']
            command = ['mpv', '--no-config', '--no-audio', '--loop-file=inf', '--no-terminal', '--fs',
                       '--vo=gpu-next', '--gpu-api='+case['api'], '--fs-screen-name='+case['output'],
                       '--screen-name='+case['output'], '--input-ipc-server='+str(ipc),
                       '--log-file='+str(root/(name+'-mpv.log')), '-v', str(films[case['film']])]
            (root/(name+'-command.json')).write_text(json.dumps({'argv': command, 'gpu_env': {k: v for k, v in env.items() if k == 'DRI_PRIME'}, 'case': case}, indent=2)+'\n')
            before = {p: p.stat().st_size for p in kwin_files}
            player = subprocess.Popen(command, env=env)
            time.sleep(4)
            js = root/'to-output.js'
            js.write_text('for (const w of workspace.windowList()) if (w.resourceClass == "mpv") { const o = workspace.screens.find(s => s.name == '+json.dumps(case['output'])+'); if (o) workspace.sendClientToScreen(w, o); }\n')
            script_id = subprocess.check_output(['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.loadScript', str(js), 'order223-'+name], text=True).strip()
            run('qdbus6', 'org.kde.KWin', '/Scripting/Script'+script_id, 'org.kde.kwin.Script.run', stdout=subprocess.DEVNULL)
            run('qdbus6', 'org.kde.KWin', '/Scripting/Script'+script_id, 'org.kde.kwin.Script.stop', stdout=subprocess.DEVNULL)
            script_id = None
            time.sleep(60)
            mark(root, case['name'])
            with (root/(name+'-ipc.jsonl')).open('w') as stream:
                deadline = time.monotonic()+180
                while time.monotonic() < deadline:
                    if player.poll() is not None:
                        raise ValueError(f'Player exited in {name}: {player.returncode}')
                    stream.write(json.dumps({'monotonic': time.monotonic(), 'properties': counters(ipc)})+'\n')
                    stream.flush()
                    time.sleep(max(0, min(1, deadline-time.monotonic())))
            mark(root, case['name']+'-end')
            player.terminate()
            player.wait(timeout=10)
            player = None
            for path in kwin_files:
                if path.name.endswith(case['output']+'.csv') and path.stat().st_size <= before[path]:
                    raise ValueError(f'KWin per-frame log did not grow: {path}')
            (root/(name+'-outputs.json')).write_text(subprocess.check_output(['kscreen-doctor', '-j'], text=True))
            time.sleep(8)
    finally:
        if player is not None and player.poll() is None:
            player.terminate()
            try:
                player.wait(timeout=10)
            except subprocess.TimeoutExpired:
                player.kill()
                player.wait()
        if script_id is not None:
            subprocess.run(['qdbus6', 'org.kde.KWin', '/Scripting/Script'+script_id, 'org.kde.kwin.Script.stop'], check=False)
        stop.set()
        logger.join()
        try:
            for p in kwin_files:
                shutil.copy2(p, root/p.name)
        finally:
            try:
                run('kscreen-doctor', *restore, stdout=(root/'doctor.log').open('a'), stderr=subprocess.STDOUT)
            finally:
                signal.signal(signal.SIGTERM, previous_term)
    (root/'matrix.done').write_text('done\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--phase', choices=('before', 'after'), required=True)
    p.add_argument('--host', help='A10 SSH alias; the script is sent over stdin only with --execute')
    action = p.add_mutually_exclusive_group()
    action.add_argument('--dry-run', action='store_true', help='print cases only, with no subprocesses or writes')
    action.add_argument('--execute', action='store_true', help='main session only, on the A10')
    p.add_argument('--select', default='.*', help='case-name regular expression for bounded bench batches')
    p.add_argument('--output', type=Path, default=Path('order223-a10'))
    p.add_argument('--kwin-log-dir', type=Path)
    p.add_argument('--versions', type=Path)
    p.add_argument('--film-2d', type=Path)
    p.add_argument('--film-3d', type=Path)
    p.add_argument('--coyote', type=Path)
    a = p.parse_args()
    selected = list(cases(a.select))
    if not selected:
        p.error('No matching cases')
    if not a.execute:
        print(json.dumps({'phase': a.phase, 'host': a.host, 'cases': selected,
                          'warm_seconds': 60, 'record_seconds': 180, 'idle_seconds': 120,
                          'screens_changed': False, 'packages_installed': False}, indent=2))
        return
    for value in ('kwin_log_dir', 'versions', 'film_2d', 'film_3d', 'coyote'):
        if getattr(a, value) is None:
            p.error('--'+value.replace('_', '-')+' is required with --execute')
    if a.host:
        arguments = sys.argv[1:]
        index = arguments.index('--host')
        del arguments[index:index+2]
        command = 'python3 - '+shlex.join(arguments)
        subprocess.run(['ssh', '--', a.host, command], input=Path(__file__).read_bytes(), check=True)
    else:
        execute(a)


if __name__ == '__main__':
    main()
