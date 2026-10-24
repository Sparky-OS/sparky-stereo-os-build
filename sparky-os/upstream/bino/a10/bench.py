#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run only in the A10's operator-authorized Wayland session, via run-a10.sh."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from session import command, outputs, mode_ids, restore_args, setup_args, verify_setup, verify_restore, Guard, place, latest_flip, verify_window
from summarize import summarize


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n')


def stop(player):
    if player and player.poll() is None:
        player.terminate()
        try:
            player.wait(timeout=10)
        except subprocess.TimeoutExpired:
            player.kill(); player.wait(timeout=5)


def mark(root, name):
    now = time.monotonic()
    with (root/'marks.csv').open('a') as handle:
        csv.writer(handle).writerow((name, f'{now:.9f}'))
    return now


def keep_rows(source, destination, offset, start, end):
    with source.open() as handle:
        header = handle.readline()
        handle.seek(offset)
        if offset:
            handle.readline()  # a partial last row at the recorded pre-case offset
        rows = [r for r in csv.reader(handle) if len(r) == 9 and r[1].isdigit()
                and start <= int(r[1])/1e9 < end]
    if not rows:
        raise RuntimeError('KWin recorded no presentations in the case interval')
    with destination.open('a') as handle:
        if handle.tell() == 0:
            handle.write(header)
        csv.writer(handle).writerows(rows)
    return len(rows)


def telemetry(path, start, end):
    with path.open() as handle:
        rows = [r for r in csv.DictReader(handle) if start <= int(r['start_ns'])/1e9 < end]
    result = {}
    for row in rows:
        event = row['event']
        result[event] = result.get(event, 0)+1
    if 'source' in result:
        result['unique_source_pts'] = len({r['pts_us'] for r in rows if r['event'] == 'source'})
    return result


def run(args):
    kit = Path(__file__).resolve().parent
    if os.environ.get('BINO_A10_INHIBITED') != '1' or os.environ.get('XDG_SESSION_TYPE') != 'wayland':
        raise RuntimeError('Use run-a10.sh in the existing Wayland session')
    if not os.environ.get('WAYLAND_DISPLAY') or not os.environ.get('DBUS_SESSION_BUS_ADDRESS'):
        raise RuntimeError('The session Wayland and D-Bus environment is required')
    hardware = {}
    for node in Path('/sys/class/drm').glob('renderD*'):
        device = node/'device'
        if (device/'vendor').exists() and (device/'device').exists():
            hardware[node.name] = [(device/'vendor').read_text().strip(), (device/'device').read_text().strip()]
    if not {('0x1002', '0x9874'), ('0x1002', '0x6660')} <= {tuple(v) for v in hardware.values()}:
        raise RuntimeError('This runner is for the reviewed Carrizo/Hainan A10; no display changes made')
    root = args.results.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root/'kwin').mkdir()
    prefix = kit/'private'
    players = {v: prefix/v/'usr/bin/bino' for v in ('published', 'candidate')}
    if not all(p.is_file() for p in players.values()):
        raise RuntimeError('Run install-private.sh first')
    pids = command('pgrep', '-x', 'kwin_wayland').split()
    if len(pids) != 1:
        raise RuntimeError(f'Expected one KWin process, found {pids}')
    pid = int(pids[0]); logdir = args.kwin_log_dir.expanduser().resolve()
    raw = {out: logdir/f'kwin perf statistics {out}.csv' for out in ('HDMI-A-1', 'eDP-1')}
    # The active output's file must already exist. A newly enabled output can create its file later.
    if not any(p.is_file() for p in raw.values()):
        raise RuntimeError('No active KWin per-frame logs; enable logging before this session')
    guard = Guard(root, pid, logdir)
    guard.activity(); guard.check()
    snapshot = outputs(); ids = mode_ids(snapshot); restore = restore_args(snapshot)
    write_json(root/'outputs-original.json', snapshot)
    write_json(root/'restore-command.json', ['kscreen-doctor', *restore])
    film = args.film.expanduser().resolve(strict=True)
    source = json.loads(command('ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_streams', '-of', 'json', str(film)))
    stream = source['streams'][0]
    rate = stream['avg_frame_rate']
    if rate == '0/0':
        raise RuntimeError('Source frame rate is unavailable')
    write_json(root/'source.json', source)
    source_hash = hashlib.sha256()
    with film.open('rb') as handle:
        while block := handle.read(8*1024*1024):
            source_hash.update(block)
            if time.monotonic()-guard.last_activity > 15:
                guard.activity(); guard.check()
    env = os.environ.copy()
    env['QT_QPA_PLATFORM'] = 'wayland'
    env.setdefault('DRI_PRIME', '1')  # measured Hainan default; an explicit operator choice wins
    env['LD_PRELOAD'] = str(kit/'libbino-observer.so')
    # Preserve the operator's GPU choice identically in both runs; record it explicitly.
    selection = {k: env[k] for k in env if k.startswith(('DRI_PRIME', 'MESA_VK_DEVICE_', 'QT_FFMPEG_', 'MEDIA_GPU_ROUTE', '__EGL_', '__GLX_'))}
    inventory = command('dpkg-query', '-W', '-f=${Package}\t${Version}\n', 'bino', 'kwin-wayland', 'libstereo-declare*', 'libqt6multimedia6', 'libgl1-mesa-dri', 'mesa-va-drivers')
    (root/'versions.txt').write_text(inventory)
    manifest = dict(status='running', source_rate=rate, film=str(film), film_sha256=source_hash.hexdigest(),
                    film_size=film.stat().st_size, kwin_pid=pid, kwin_log_dir=str(logdir),
                    duration=args.duration, warmup=args.warmup, gpu_environment=selection, hardware=hardware,
                    binaries={v:dict(path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for v,p in players.items()})
    write_json(root/'run.json', manifest)
    player = None
    try:
        for setup, extended, output in [('tv-3d', False, 'HDMI-A-1'), ('extended-hdmi', True, 'HDMI-A-1'), ('extended-edp', True, 'eDP-1')]:
            guard.expected = None
            (root/(setup+'-doctor.txt')).write_text(command('kscreen-doctor', *setup_args(ids, extended)))
            guard.wait(args.settle)
            guard.expected = (ids, extended)
            verify_setup(outputs(), ids, extended)
            for variant in ('published', 'candidate'):
                guard.activity(); guard.check()
                name = f'{setup}/{output}/{variant}/3d'
                case = root/(setup+'-'+variant); case.mkdir()
                if not raw[output].is_file():
                    raise RuntimeError(f'Missing KWin CSV for {output}')
                identity = raw[output].stat(); offset = identity.st_size
                observer = case/'observer.csv'; frame_trace = case/'bino.csv'
                runenv = dict(env, BINO_OBSERVER_TRACE=str(observer), BINO_FRAME_TRACE=str(frame_trace))
                # Keep identical, isolated settings for the two executables; never edit the user's Bino preferences.
                runenv['XDG_CONFIG_HOME'] = str(case/'config')
                argv = [str(players[variant]), '--log-level', 'info', '-l', 'one', '-i', 'left-right-half']
                if variant == 'published':
                    argv += ['-o', 'left-right']
                argv.append(str(film))
                write_json(case/'command.json', dict(argv=argv, environment={k:runenv[k] for k in ('QT_QPA_PLATFORM','LD_PRELOAD','BINO_OBSERVER_TRACE','BINO_FRAME_TRACE','XDG_CONFIG_HOME')}, gpu_environment=selection))
                print(name, flush=True)
                with (case/'bino.log').open('w') as log:
                    player = subprocess.Popen(argv, env=runenv, stdout=log, stderr=subprocess.STDOUT)
                    guard.player = player
                    guard.wait(8)
                    place(case, player.pid, output, f'bino-a10-{os.getpid()}-{setup}-{variant}')
                    guard.wait(args.warmup)
                    verify_window(observer, output)
                    if time.monotonic()-latest_flip(raw[output]) > 15:
                        raise RuntimeError('KWin CSV is stale or uses a different clock')
                    write_json(case/'outputs-start.json', outputs())
                    start = mark(root, name)
                    guard.wait(args.duration)
                    verify_window(observer, output)
                    end = mark(root, name+'-end')
                    # KWin uses buffered std::fstream output. Keep playing until the end mark is on disk.
                    deadline = time.monotonic()+20
                    while latest_flip(raw[output]) < end:
                        if time.monotonic() > deadline:
                            raise RuntimeError('KWin did not flush through the end mark')
                        guard.wait(2)
                    if raw[output].stat().st_ino != identity.st_ino or raw[output].stat().st_size < offset:
                        raise RuntimeError('KWin log rotated or was truncated during the case')
                    count = keep_rows(raw[output], root/'kwin'/raw[output].name, offset, start, end)
                    observed = telemetry(observer, start, end)
                    if observed.get('source', 0) < 2 or observed.get('unique_source_pts', 0) < 2:
                        raise RuntimeError('Source timestamps were not observed')
                    if variant == 'published' and observed.get('texture_upload', 0) < 2:
                        raise RuntimeError('Published upload observation is missing')
                    native = telemetry(frame_trace, start, end) if variant == 'candidate' else None
                    if native is not None and native.get('cpu_upload', 0)+native.get('texture_import', 0) < 2:
                        raise RuntimeError('Candidate upload/import trace is missing')
                    write_json(case/'counts.json', dict(kwin_frames=count, observer=observed, bino=native, start=start, end=end))
                    write_json(case/'outputs-end.json', outputs())
                    stop(player); guard.player = player = None
                guard.wait(8)
        manifest['status'] = 'complete'
    except BaseException as error:
        manifest.update(status='confounded', reason=str(error) or type(error).__name__)
        raise
    finally:
        stop(player); guard.player = None; guard.expected = None
        try:
            (root/'restore.log').write_text(command('kscreen-doctor', *restore))
            restored = outputs()
            write_json(root/'outputs-restored.json', restored)
            verify_restore(snapshot, restored)
        except BaseException as error:
            manifest.update(status='confounded', restore_error=str(error))
        write_json(root/'run.json', manifest)
    print(summarize(root))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--film', required=True, type=Path)
    parser.add_argument('--kwin-log-dir', required=True, type=Path)
    parser.add_argument('--results', required=True, type=Path)
    parser.add_argument('--duration', type=float, default=180)
    parser.add_argument('--warmup', type=float, default=60)
    parser.add_argument('--settle', type=float, default=40)
    args = parser.parse_args()
    if min(args.duration, args.warmup, args.settle) <= 0:
        parser.error('Durations must be positive')
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    run(args)
