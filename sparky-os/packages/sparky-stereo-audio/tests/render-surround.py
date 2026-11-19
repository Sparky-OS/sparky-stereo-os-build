#!/usr/bin/python3 -I
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Private PipeWire/WirePlumber test. No host device or session is required.

Run in a network-disabled container as a normal user under dbus-run-session.
The 5.1 signal contains separated impulses for every speaker, including LFE.
"""
import ctypes
import importlib.util
import json
import math
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import time

import numpy as np
from scipy.signal import correlate

spec = importlib.util.spec_from_file_location('surround', Path(__file__).resolve().parents[1] / 'lib/surround.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


def wait_for(predicate, seconds=8):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError('timeout waiting for private graph')


def nodes():
    p = subprocess.run(['pw-dump'], capture_output=True, text=True)
    if p.returncode:
        return []
    return [o for o in json.loads(p.stdout) if o['type'] == 'PipeWire:Interface:Node']


def reference(azimuth, rate):
    lib = ctypes.CDLL('libmysofa.so.1')
    lib.mysofa_open.argtypes = [ctypes.c_char_p, ctypes.c_float,
                                ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
    lib.mysofa_open.restype = ctypes.c_void_p
    lib.mysofa_getfilter_float.argtypes = [ctypes.c_void_p, ctypes.c_float, ctypes.c_float, ctypes.c_float] + [ctypes.POINTER(ctypes.c_float)] * 4
    lib.mysofa_close.argtypes = [ctypes.c_void_p]
    count, error = ctypes.c_int(), ctypes.c_int()
    handle = lib.mysofa_open(s.KEMAR.encode(), rate, ctypes.byref(count), ctypes.byref(error))
    assert handle and error.value == 0, error.value
    try:
        left = (ctypes.c_float * count.value)()
        right = (ctypes.c_float * count.value)()
        dl, dr = ctypes.c_float(), ctypes.c_float()
        a = math.radians(azimuth)
        lib.mysofa_getfilter_float(handle, 1.4 * math.cos(a), 1.4 * math.sin(a), 0,
                                  left, right, ctypes.byref(dl), ctypes.byref(dr))
        assert dl.value == dr.value == 0, 'SOFA plugin drops external delays'
        return np.column_stack([np.array(left), np.array(right)])
    finally:
        lib.mysofa_close(handle)


def main():
    with tempfile.TemporaryDirectory(prefix='as21-render-', dir='/work') as folder:
        root = Path(folder)
        runtime = root / 'runtime'
        runtime.mkdir(mode=0o700)
        os.environ['XDG_RUNTIME_DIR'] = str(runtime)
        os.environ['XDG_CONFIG_HOME'] = str(root / 'config')
        os.environ['XDG_STATE_HOME'] = str(root / 'state')
        os.environ['HOME'] = str(root)
        conf = root / 'config/pipewire/pipewire.conf.d'
        conf.mkdir(parents=True)
        (conf / 'test.conf').write_text(json.dumps({
            'context.properties': {'default.clock.allowed-rates': [44100, 48000, 96000]},
            'context.objects': [{'factory': 'adapter', 'args': {
                'factory.name': 'support.null-audio-sink', 'node.name': 'as21-headphones',
                'media.class': 'Audio/Sink', 'device.form-factor': 'headphone',
                'audio.position': ['FL', 'FR'], 'audio.channels': 2}}]}))
        automatic = os.environ.get('AS21_AUTOMATIC') == '1'
        if automatic and os.environ.get('AS21_BASELINE') != '1':
            wpconf = root / 'config/wireplumber/wireplumber.conf.d'
            wpconf.mkdir(parents=True)
            source_dir = Path(__file__).resolve().parents[1] / 'wireplumber'
            text = (source_dir / '00-sparky-stereo-surround.conf').read_text()
            text = text.replace('name = sparky-stereo-audio.lua', 'name = "' + str(source_dir / 'sparky-stereo-audio.lua') + '"')
            (wpconf / '00-surround.conf').write_text(text)
        processes = []
        logs = []
        def start(command, name, **kwargs):
            log = open('/evidence/render-' + name + '.log', 'w')
            logs.append(log)
            p = subprocess.Popen(command, stdout=log, stderr=log, **kwargs)
            processes.append(p)
            return p
        try:
            start(['pipewire'], 'pipewire')
            wait_for(lambda: (runtime / 'pipewire-0').exists())
            start(['wireplumber'], 'wireplumber')
            wait_for(lambda: any(n['info']['props'].get('node.name') == 'as21-headphones' for n in nodes()))
            layout = os.environ.get('AS21_LAYOUT', '5.1')
            positions = s.LAYOUTS[layout]
            args = s.module_args('as21-binaural', 'as21-headphones', s.binaural(layout),
                                 positions, 'as21')
            config = root / 'filter.conf'
            config.write_text(json.dumps(s.client_config(args)))
            filter_process = None
            if not automatic:
                filter_process = start(['pipewire', '-c', str(config)], 'filter')
                wait_for(lambda: any(n['info']['props'].get('node.name') == 'as21-binaural' for n in nodes()))
            results = []
            for rate in (48000, 96000):
                frames = 3 * rate
                source = np.zeros((frames, len(positions)), dtype='<f4')
                offsets = [rate // 2 + i * rate // 3 for i in range(len(positions))]
                for i, offset in enumerate(offsets):
                    source[offset, i] = 0.1
                raw = root / 'source.raw'
                source.tofile(raw)
                capture = root / 'capture.raw'
                with open(capture, 'wb') as output:
                    rec = subprocess.Popen(['pw-record', '--raw', '--properties', 'stream.capture.sink=true', '--target', 'as21-headphones', '--rate', str(rate),
                                            '--channels', '2', '--channel-map', 'FL,FR', '--format', 'f32', '-'],
                                           stdout=output, stderr=subprocess.DEVNULL)
                    processes.append(rec)
                    time.sleep(0.3)
                    player = subprocess.Popen(['pw-play', '--raw', '--target', 'as21-headphones' if automatic else 'as21-binaural', '--rate', str(rate),
                                    '--channels', str(len(positions)), '--channel-map', ','.join(positions),
                                    '--format', 'f32', '-'], stdin=open(raw, 'rb'))
                    processes.append(player)
                    time.sleep(0.3)
                    if automatic:
                        Path('/evidence/automatic-graph.json').write_text(subprocess.check_output(['pw-dump'], text=True))
                    player.wait(timeout=15)
                    time.sleep(0.3)
                    rec.send_signal(signal.SIGINT)
                    rec.wait(timeout=5)
                received = np.fromfile(capture, dtype='<f4').reshape(-1, 2)
                assert len(received) > frames, (rate, len(received))
                predicted = np.zeros((frames, 2), dtype='<f4')
                refs = []
                for i, channel in enumerate(positions):
                    ir = reference(s.ANGLES[channel], rate) * 0.1
                    refs.append(ir)
                    predicted[offsets[i]:offsets[i] + len(ir)] += ir
                alignment = int(np.argmax(correlate(received[:, 0], predicted[:, 0], mode='full')) - len(predicted) + 1)
                assert alignment >= 0, alignment
                actual = received[alignment:alignment + frames]
                error = float(np.max(np.abs(actual - predicted)))
                channels = []
                for i, channel in enumerate(positions):
                    got = actual[offsets[i]:offsets[i] + len(refs[i])]
                    peaks = [int(np.argmax(np.abs(got[:, ear]))) for ear in (0, 1)]
                    expected = [int(np.argmax(np.abs(refs[i][:, ear]))) for ear in (0, 1)]
                    channels.append({'speaker': channel, 'peak_L_R': peaks, 'expected_peak_L_R': expected,
                                     'interaural_peak_samples': peaks[1] - peaks[0]})
                    assert peaks == expected, channels[-1]
                results.append({'layout': layout, 'rate': rate, 'max_error': error, 'channels': channels})
                assert error < 2e-6, results[-1]
            if filter_process:
                filter_process.terminate()
                filter_process.wait(timeout=5)
            wait_for(lambda: not any(n['info']['props'].get('node.name', '').startswith(('as21-binaural', 'sparky.audio.')) for n in nodes()))
            Path('/evidence/' + ('automatic' if automatic else 'render') + '-' + layout + '-results.json').write_text(json.dumps(results, indent=2) + '\n')
            print(json.dumps(results, indent=2))
        finally:
            for p in reversed(processes):
                if p.poll() is None:
                    p.terminate()
                    try:
                        p.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        p.kill()
                        p.wait()
            for log in logs:
                log.close()


if __name__ == '__main__':
    main()
