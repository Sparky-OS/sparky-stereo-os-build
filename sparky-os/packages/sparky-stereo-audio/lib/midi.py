# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""MIDI choices and the existing Debian FluidSynth user unit's on-demand renderer."""
import json
import os
from pathlib import Path
import signal
import select
import socket
import subprocess
import time
from session import report, clear, Parser, snapshot


class MissingFont(FileNotFoundError):
    pass


def config_path():
    return Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'sparky-stereo-audio/midi.json'


def choices():
    p = config_path()
    data = json.loads(p.read_text()) if p.exists() else {}
    if not isinstance(data, dict) or set(data) - {'font', 'driver', 'connect'}:
        raise ValueError(str(p))
    if data.get('driver', 'auto') not in ('auto', 'alsa_seq', 'jack') or data.get('connect', 'no') not in ('yes', 'no'):
        raise ValueError(str(p))
    font = data.get('font', 'auto')
    if not isinstance(font, str) or (font != 'auto' and not os.path.isabs(font)):
        raise ValueError(str(p))
    return data


def font_path(data):
    # Debian's alternatives already prefer an installed larger font. No CPU threshold is invented here.
    font = data.get('font', 'auto')
    personal = Path.home() / '.config/fluidsynth'
    if font == 'auto' and personal.is_file():
        import shlex
        for line in personal.read_text().splitlines():
            if line.strip().startswith('SOUND_FONT='):
                words = shlex.split(line.strip().split('=', 1)[1])
                if len(words) != 1 or not os.path.isabs(words[0]):
                    raise ValueError(str(personal))
                font = words[0]
    paths = ['/usr/share/sounds/sf2/default-GM.sf2', '/usr/share/sounds/sf3/default-GM.sf3',
             '/usr/share/sounds/sf2/TimGM6mb.sf2'] if font == 'auto' else [font]
    for p in paths:
        if Path(p).is_file() and os.access(p, os.R_OK):
            return str(Path(p).resolve())
    raise MissingFont(font)


def driver(data):
    selected = data.get('driver', 'auto')
    return ('alsa_seq' if os.access('/dev/snd/seq', os.R_OK | os.W_OK) else 'jack') if selected == 'auto' else selected


def show(say):
    try:
        data = choices()
        print(say(50, font_path(data)))
        print(say(51, driver(data), say(33 if data.get('connect') == 'yes' else 34)))
        print(say(52))
    except MissingFont as exc:
        print(say(54, str(exc)))
    except (OSError, ValueError) as exc:
        print(say(53, str(exc)))


def serve(data, say):
    backend = driver(data)
    if data.get('driver', 'auto') == 'auto' and backend == 'jack':
        report(say, 'midi-sequencer', 55)
    else:
        clear('midi-sequencer')
    command = ['/usr/lib/sparky-stereo-midi/render', font_path(data), backend, data.get('connect', 'no')]
    if backend == 'jack':
        command.insert(0, 'pw-jack')
    child = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
    def stop(signum, frame):
        child.terminate()
    old = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        if not select.select([child.stdout], [], [], 30)[0] or child.stdout.readline().strip() != 'READY':
            raise RuntimeError('FluidSynth: MIDI endpoint startup failed')
        clear('midi-font'); clear('midi')
        address = os.environ.get('NOTIFY_SOCKET')
        if address:
            if address.startswith('@'):
                address = '\0' + address[1:]
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notify:
                notify.connect(address); notify.sendall(b'READY=1')
        code = child.wait()
    finally:
        if child.poll() is None:
            child.terminate(); child.wait(timeout=10)

        for sig, handler in old.items():
            signal.signal(sig, handler)
    if code:
        raise RuntimeError('FluidSynth: %d' % code)
    clear('midi')
    return 0


def midi_ports(player=None):
    objects = snapshot()
    nodes = {x['id']: x['info']['props'] for x in objects if x['type'] == 'PipeWire:Interface:Node'}
    found = {}
    for obj in objects:
        if obj['type'] != 'PipeWire:Interface:Port':
            continue
        props = obj['info']['props']
        if props.get('format.dsp') != '8 bit raw midi':
            continue
        name = nodes.get(props.get('node.id'), {}).get('node.name')
        if (name == 'sparky-midi' and props.get('port.direction') == 'in') or (name == player and props.get('port.direction') == 'out'):
            if name in found:
                raise RuntimeError('multiple MIDI ports: ' + name)
            found[name] = obj['id']
    return found


def play(path, data):
    if driver(data) == 'alsa_seq':
        result = subprocess.run(['aplaymidi', '-l'], capture_output=True, text=True, check=True)
        import re
        ports = [m.group(1) for line in result.stdout.splitlines() if 'Sparky General MIDI' in line
                 and (m := re.match(r'\s*(\d+:\d+)\s', line))]
        if len(ports) != 1:
            raise RuntimeError('Sparky General MIDI: ' + str(ports))
        return subprocess.run(['aplaymidi', '-p', ports[0], '--', path], check=True).returncode
    name = 'sparky-midi-player-%d' % os.getpid()
    child = subprocess.Popen(['pw-midiplay', '--target', '0', '--properties', 'node.name=' + name, '--', path])
    try:
        for _ in range(50):
            ports = midi_ports(name)
            if name in ports and 'sparky-midi' in ports:
                subprocess.run(['pw-link', str(ports[name]), str(ports['sparky-midi'])], check=True)
                code = child.wait()
                if code:
                    raise RuntimeError('pw-midiplay: %d' % code)
                return 0
            if child.poll() is not None:
                raise RuntimeError('pw-midiplay: %d' % child.returncode)
            time.sleep(.1)
        raise RuntimeError('MIDI port: timeout')
    finally:
        if child.poll() is None:
            child.terminate()
        child.wait(timeout=5)


def command(argv, say):
    parser = Parser(add_help=False)
    parser.add_argument('--font')
    parser.add_argument('--driver', choices=('auto', 'alsa_seq', 'jack'))
    parser.add_argument('--connect', choices=('yes', 'no'))
    parser.add_argument('--service', choices=('on', 'off'))
    parser.add_argument('--serve', action='store_true')
    parser.add_argument('--play')
    parser.add_argument('--emulator-error', choices=('DOSBox-Staging',))
    parser.add_argument('--emulator-ready', choices=('DOSBox-Staging', 'Munt'))
    parser.add_argument('--rom-error', choices=('Munt', 'DOSBox-Staging'))
    try:
        args = parser.parse_args(argv)
        if args.emulator_error:
            report(say, 'midi-emulator-' + args.emulator_error.lower(), 53, args.emulator_error)
            return 1
        if args.emulator_ready:
            clear('midi-emulator-' + args.emulator_ready.lower())
            clear('midi-rom-' + args.emulator_ready.lower())
            return 0
        if args.rom_error:
            report(say, 'midi-rom-' + args.rom_error.lower(), 56, args.rom_error)
            return 1
        data = choices()
        changed = False
        for key in ('font', 'driver', 'connect'):
            value = getattr(args, key)
            if value is not None:
                data[key] = value
                changed = True
        if changed:
            font_path(data)
            # Validate everything before replacing the person's one authoritative choices file.
            if data.get('font', 'auto') != 'auto' and not os.path.isabs(data['font']):
                raise ValueError(data['font'])
            p = config_path(); p.parent.mkdir(parents=True, exist_ok=True)
            import tempfile
            with tempfile.NamedTemporaryFile(mode='w', dir=p.parent, delete=False) as f:
                json.dump(data, f); f.write('\n'); temporary = f.name
            previous = p.read_bytes() if p.exists() else None
            os.replace(temporary, p)
            try:
                subprocess.run(['systemctl', '--user', 'try-restart', 'sparky-stereo-midi.service'], check=True)
            except subprocess.SubprocessError:
                if previous is None:
                    p.unlink()
                else:
                    with tempfile.NamedTemporaryFile(mode='wb', dir=p.parent, delete=False) as old:
                        old.write(previous); rollback = old.name
                    os.replace(rollback, p)
                raise
        if args.service:
            commands = [['mask', '--now']] if args.service == 'off' else [['unmask'], ['start']]
            for cmd in commands:
                subprocess.run(['systemctl', '--user', *cmd, 'sparky-stereo-midi.service'], check=True)
        if args.serve:
            return serve(data, say)
        if args.play:
            path = str(Path(args.play).resolve(strict=True))
            # Starting an already-running service is harmless. A masked service stays the person's choice.
            subprocess.run(['systemctl', '--user', 'start', 'sparky-stereo-midi.service'], check=True)
            return play(path, data)
        show(say)
        clear('midi')
        return 0
    except MissingFont as exc:
        report(say, 'midi-font', 54, str(exc))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        report(say, 'midi', 53, str(exc))
    return 1
