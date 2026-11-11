#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
"""ORDER 346a, row U33: is the switch of a 3D film to software decoding told to the person?

Plays one film in a fresh headless Weston with mpv's terminal OSD forced on (--term-osd=force puts the OSD's messages
on the terminal too, mpv's player/osd.c) and records: the decoder at the end (hwdec-current over IPC), the terminal's
output (where the OSD message appears), and the log file's lines about the decoding path with their level. Writes
NAME.json, NAME-terminal.txt and NAME-mpv.log. Run inside a container with the GPU's render node; never on a desktop.
Usage: mpv-told.py --name NAME --film FILM --out DIR [--lang LANG] [MPV_ARG...]"""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def ask(path, name):
    sock = socket.socket(socket.AF_UNIX)
    sock.connect(path)
    sock.settimeout(10)
    sock.sendall(json.dumps({'command': ['get_property', name], 'request_id': 1}).encode() + b'\n')
    buffer = b''
    while True:
        while b'\n' not in buffer:
            buffer += sock.recv(65536)
        line, buffer = buffer.split(b'\n', 1)
        message = json.loads(line)
        if message.get('request_id') == 1:
            sock.close()
            return message.get('data')


def wait_for(predicate, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.1)
    return False


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--name', required=True)
    p.add_argument('--film', required=True)
    p.add_argument('--out', required=True, type=Path)
    p.add_argument('--lang', default='C.UTF-8')
    p.add_argument('--play', type=float, default=6.0)
    p.add_argument('mpv_args', nargs='*')
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='mpv-told-'))
    run.chmod(0o700)
    env = {k: v for k, v in os.environ.items()
           if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'MEDIA_GPU_ROUTE_COPY_BACK', 'LANGUAGE', 'LC_ALL', 'LC_MESSAGES')}
    env.update(XDG_RUNTIME_DIR=str(run), XDG_CONFIG_HOME=str(run / 'config'), XDG_CONFIG_DIRS=str(run / 'xdg'), LANG=a.lang)
    weston = subprocess.Popen(['weston', '--backend=headless', '--renderer=gl', '--width=1920', '--height=1080',
                               '--socket=wayland-case', '--idle-time=0'], env=env,
                              stdout=(a.out / f'{a.name}-weston.log').open('w'), stderr=subprocess.STDOUT)
    if not wait_for(lambda: (run / 'wayland-case').exists(), 10):
        raise SystemExit('weston did not start')
    env['WAYLAND_DISPLAY'] = 'wayland-case'
    log = a.out / f'{a.name}-mpv.log'
    terminal = a.out / f'{a.name}-terminal.txt'
    sock = str(run / 'mpv.sock')
    command = ['mpv', '--no-config', '--no-audio', '--keep-open=always', '--vo=gpu-next', '--gpu-api=vulkan',
               '--term-osd=force', f'--input-ipc-server={sock}', f'--log-file={log}', *a.mpv_args, a.film]
    with terminal.open('w') as out:
        player = subprocess.Popen(command, env=env, stdout=out, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        try:
            if not wait_for(lambda: os.path.exists(sock), 15):
                raise SystemExit('mpv did not open its IPC socket')
            time.sleep(a.play)
            hwdec = ask(sock, 'hwdec-current')
            subprocess.run(['true'])
            sock_quit = socket.socket(socket.AF_UNIX)
            sock_quit.connect(sock)
            sock_quit.sendall(b'{"command": ["quit"]}\n')
            sock_quit.close()
            player.wait(timeout=15)
        finally:
            if player.poll() is None:
                player.kill()
                player.wait()
            weston.terminate()
            weston.wait(timeout=10)
    lines = log.read_text(errors='replace').splitlines() if log.exists() else []
    marks = ('Decoding in software', 'Dekodierung in Software', 'Keeping hardware decoding', 'Asking for software decoding',
             'Using hardware decoding', 'Using software decoding')
    result = {'name': a.name, 'argv': command, 'lang': a.lang, 'hwdec_current_end': hwdec,
              'log': [l for l in lines if any(m in l for m in marks)]}
    (a.out / f'{a.name}.json').write_text(json.dumps(result, indent=1, ensure_ascii=False) + '\n')
    print(a.name, hwdec)


if __name__ == '__main__':
    main()
