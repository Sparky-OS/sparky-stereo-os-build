#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
"""Play one film in a fresh headless Weston and record mpv's decoder choice.

Writes NAME.json (properties sampled over IPC and the relevant log lines),
NAME-mpv.log and, with --screenshot-at, NAME.png (mpv's "video" screenshot,
rendered by the video output from the frame at that time).
Run inside a container with the GPU's render node; never on a desktop."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

PROPERTIES = ('hwdec-current', 'hwdec-interop', 'video-params', 'video-out-params', 'dwidth', 'dheight',
              'estimated-vf-fps', 'frame-drop-count', 'decoder-frame-drop-count', 'time-pos', 'video-codec')
LOG_MARKS = ('Using hardware decoding', 'Using software decoding', 'Not copying pictures back',
             'Inserting stereo conversion filter', 'Declaring the 3D video as it is',
             'Asking for software decoding', 'Decoding in software: the filters need',
             'no DRM modifiers', 'dmabuf interop', 'VAAPI hwdec only works', 'auto_scale_0: w:',
             'Attempting next decoding method', 'Falling back to software')


class Ipc:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.connect(path)
        self.sock.settimeout(10)
        self.buffer = b''
        self.request = 0

    def command(self, *args):
        self.request += 1
        self.sock.sendall(json.dumps({'command': list(args), 'request_id': self.request}).encode() + b'\n')
        while True:
            while b'\n' not in self.buffer:
                self.buffer += self.sock.recv(65536)
            line, self.buffer = self.buffer.split(b'\n', 1)
            message = json.loads(line)
            if message.get('request_id') == self.request:
                return message

    def get(self, name):
        reply = self.command('get_property', name)
        return reply.get('data') if reply.get('error') == 'success' else None


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
    p.add_argument('--vo', default='gpu-next')
    p.add_argument('--api', default='vulkan')
    p.add_argument('--a10', action='store_true',
                   help='hide VK_EXT_image_drm_format_modifier and Vulkan Video decode, as RADV on the A10')
    p.add_argument('--layer-dir', type=Path, help='directory of the hide-modifiers test layer')
    p.add_argument('--machine-record', help='CopyBack value written to a machine sparky-stereo-graphicsrc')
    p.add_argument('--play', type=float, default=4.0)
    p.add_argument('--screenshot-at', type=float)
    p.add_argument('mpv_args', nargs='*')
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='mpv-case-'))
    run.chmod(0o700)
    env = {k: v for k, v in os.environ.items() if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'MEDIA_GPU_ROUTE_COPY_BACK')}
    env.update(XDG_RUNTIME_DIR=str(run), XDG_CONFIG_HOME=str(run/'config'), XDG_CONFIG_DIRS=str(run/'xdg'))
    if a.machine_record:
        (run/'xdg').mkdir()
        (run/'xdg/sparky-stereo-graphicsrc').write_text(f'[Decoding]\nCopyBack={a.machine_record}\n')
    if a.a10:
        env.update(VK_ADD_LAYER_PATH=str(a.layer_dir), VK_INSTANCE_LAYERS='VK_LAYER_SPARKY_test_hide_drm_format_modifier',
                   SPARKY_TEST_HIDE_EXTENSIONS='VK_KHR_video_decode_queue')
    weston = None
    if a.vo != 'null':
        weston = subprocess.Popen(['weston', '--backend=headless', '--renderer=gl', '--width=1920', '--height=1080',
                                   '--socket=wayland-case', '--idle-time=0'], env=env,
                                  stdout=(a.out/f'{a.name}-weston.log').open('w'), stderr=subprocess.STDOUT)
        if not wait_for(lambda: (run/'wayland-case').exists(), 10):
            raise SystemExit('weston did not start')
        env['WAYLAND_DISPLAY'] = 'wayland-case'
    log = a.out/f'{a.name}-mpv.log'
    sock = run/'mpv.sock'
    command = ['mpv', '--no-config', '--no-audio', '--keep-open=always', f'--vo={a.vo}', f'--gpu-api={a.api}',
               f'--input-ipc-server={sock}', f'--log-file={log}', '-v', *a.mpv_args, a.film]
    player = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = {'name': a.name, 'argv': command, 'a10_emulation': a.a10, 'machine_record': a.machine_record}
    try:
        if not wait_for(lambda: sock.exists(), 15):
            raise SystemExit('mpv did not open its IPC socket')
        ipc = Ipc(str(sock))
        wait_for(lambda: ipc.get('hwdec-current') is not None and ipc.get('video-out-params'), 15)
        time.sleep(a.play)
        result['properties'] = {name: ipc.get(name) for name in PROPERTIES}
        if a.screenshot_at is not None:
            ipc.command('set_property', 'pause', True)
            ipc.command('seek', a.screenshot_at, 'absolute+exact')
            wait_for(lambda: abs((ipc.get('time-pos') or -1) - a.screenshot_at) < 0.01, 10)
            time.sleep(1.0)
            shot = a.out/f'{a.name}.png'
            result['screenshot_time'] = ipc.get('time-pos')
            result['screenshot'] = ipc.command('screenshot-to-file', str(shot), 'video').get('error')
            wait_for(shot.exists, 10)
        ipc.command('quit')
        player.wait(timeout=15)
    finally:
        if player.poll() is None:
            player.kill()
            player.wait()
        if weston:
            weston.terminate()
            weston.wait(timeout=10)
    lines = log.read_text(errors='replace').splitlines() if log.exists() else []
    result['log'] = [line for line in lines if any(mark in line for mark in LOG_MARKS)]
    (a.out/f'{a.name}.json').write_text(json.dumps(result, indent=1) + '\n')
    print(a.name, result['properties'].get('hwdec-current'), (result['properties'].get('video-out-params') or {}).get('pixelformat'))


if __name__ == '__main__':
    main()
