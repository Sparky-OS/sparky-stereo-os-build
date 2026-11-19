# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""The audio engine's session interface; WirePlumber owns saved routing options."""
import argparse
import codecs
import json
import os
import subprocess
import time
from surround import headphone

SETTING = 'sparky.audio.outputs'
CODECS = {'AC3': 'ac3-iec61937', 'EAC3': 'eac3-iec61937', 'DTS': 'dts-iec61937',
          'TRUEHD': 'truehd-iec61937', 'DTSHD': 'dtshd-iec61937'}


class UnsupportedDelay(ValueError):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise ValueError(message)


def report(say, key, number, *args):
    print(say(number, *args))
    if not os.environ.get('SPARKY_STEREO_AUDIO_ROOT'):
        subprocess.run(['sparky-stereo-problems', 'keep', 'sparky-stereo-audio', key,
                        'LOCAL%d' % number] + [str(a) for a in args], check=True)


def clear(key):
    if not os.environ.get('SPARKY_STEREO_AUDIO_ROOT'):
        subprocess.run(['sparky-stereo-problems', 'clear', 'sparky-stereo-audio', key], check=True)


def snapshot():
    r = subprocess.run(['pw-dump'], check=True, capture_output=True, text=True, timeout=10)
    return json.loads(r.stdout)


def outputs(objects):
    for obj in objects:
        if obj.get('type') == 'PipeWire:Interface:Metadata' and obj.get('props', {}).get('metadata.name') == 'sm-settings':
            for entry in obj.get('metadata', []):
                if entry.get('key') == SETTING:
                    result = json.loads(entry['value'])
                    if isinstance(result, dict):
                        return result
    raise RuntimeError(SETTING)


def validate_profile(path, kind):
    if not os.path.isabs(path) or not os.path.isfile(path) or not os.access(path, os.R_OK):
        raise ValueError(path)
    if kind == 'sofa':
        # PipeWire 1.6.9 ignores external Data.Delay. Refuse that loss explicitly;
        # embedded delays in the actual response are preserved, as in MIT KEMAR.
        r = subprocess.run(['mysofa2json', path], capture_output=True, text=True, timeout=30, check=True)
        data = json.loads(r.stdout)
        delays = data.get('Variables', {}).get('Data.Delay', {}).get('Values', [])
        if any(value != 0 for value in delays):
            raise UnsupportedDelay('Data.Delay')
    else:
        import struct
        with open(path, 'rb') as f:
            if f.read(4) != b'RIFF':
                raise ValueError('RIFF')
            f.read(4)
            if f.read(4) != b'WAVE':
                raise ValueError('WAVE')
            while True:
                header = f.read(8)
                if len(header) != 8:
                    raise ValueError('fmt')
                name, size = struct.unpack('<4sI', header)
                if name == b'fmt ':
                    data = f.read(min(size, 40))
                    if len(data) < 16 or struct.unpack_from('<H', data, 2)[0] != 14:
                        raise ValueError('14 channels')
                    break
                f.seek(size + (size & 1), 1)


def configure(argv, say):
    parser = Parser(add_help=False)
    parser.add_argument('--output', required=True)
    parser.add_argument('--layout', choices=('auto', '5.1', '7.1'))
    parser.add_argument('--headphones', choices=('auto', 'yes', 'no'))
    parser.add_argument('--enabled', choices=('yes', 'no'))
    parser.add_argument('--matrix', choices=('off', 'decode', 'upmix'))
    parser.add_argument('--profile')
    parser.add_argument('--kind', choices=('sofa', 'hesuvi'), default='sofa')
    try:
        args = parser.parse_args(argv)
        current = outputs(snapshot())
        options = current.setdefault(args.output, {})
        if args.profile:
            if args.profile == 'default':
                options.pop('hrtf', None)
                options.pop('kind', None)
            else:
                validate_profile(args.profile, args.kind)
                options.update(hrtf=args.profile, kind=args.kind)
        for key in ('layout', 'headphones', 'enabled', 'matrix'):
            value = getattr(args, key)
            if value is None:
                continue
            if value == 'auto':
                options.pop(key, None)
            else:
                options[key] = value if key in ('layout', 'matrix') else value == 'yes'
        options['revision'] = int(options.get('revision', 0)) + 1
        subprocess.run(['wpctl', 'settings', '--save', SETTING, json.dumps(json.dumps(current))],
                       check=True, capture_output=True, text=True, timeout=10)
        clear('profile')
        clear('options')
        return 0
    except UnsupportedDelay:
        report(say, 'profile', 29)
        return 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report(say, 'options', 27, str(error))
        return 1


def pulse_sinks():
    result = subprocess.run(['pactl', '--format=json', 'list', 'sinks'], check=True,
                            capture_output=True, text=True, timeout=10)
    return json.loads(result.stdout)


def formats(sink):
    result = set()
    for value in sink.get('formats', []):
        if isinstance(value, dict):
            value = value.get('encoding', '')
        result.add(value.split(',')[0].strip())
    return result


def detected_codecs(sink, objects):
    props = sink.get('properties', {})
    raw = props.get('iec958.codecs.detected')
    if raw:
        return json.loads(raw)
    # ACP attaches the ELD-derived list to its port, not a global card union.
    active = sink.get('active_port')
    for obj in objects:
        if obj.get('type') != 'PipeWire:Interface:Device':
            continue
        if str(obj.get('id')) != str(props.get('device.id')):
            continue
        for route in obj.get('info', {}).get('params', {}).get('EnumRoute', []):
            if route.get('name') == active:
                raw = route.get('info', {}).get('iec958.codecs.detected')
                return json.loads(raw) if isinstance(raw, str) else (raw or [])
    return []


def passthrough(argv, say):
    parser = Parser(add_help=False)
    parser.add_argument('--output', required=True)
    parser.add_argument('--codec', action='append', default=[])
    try:
        args = parser.parse_args(argv)
        sink = next((s for s in pulse_sinks() if s['name'] == args.output), None)
        if sink is None:
            raise ValueError(args.output)
        selected = formats(sink) | {'pcm'}
        detected = detected_codecs(sink, snapshot())
        for change in args.codec:
            codec, value = change.split('=', 1)
            if codec not in CODECS or value not in ('auto', 'on', 'off'):
                raise ValueError(change)
            enabled = value == 'on' or (value == 'auto' and codec in detected)
            if enabled:
                selected.add(CODECS[codec])
            else:
                selected.discard(CODECS[codec])
        if args.codec:
            subprocess.run(['pactl', 'set-sink-formats', str(sink['index']), ';'.join(sorted(selected))],
                           capture_output=True, text=True, check=True, timeout=10)
            deadline = time.monotonic() + 2
            while True:
                current = next(s for s in pulse_sinks() if s['name'] == args.output)
                if formats(current) == selected:
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError(args.output)
                time.sleep(0.05)
        print(say(31, args.output, ' '.join(sorted(selected)), ' '.join(sorted(detected))))
        clear('passthrough')
        clear('passthrough:' + args.output)
        for change in args.codec:
            clear('passthrough:' + args.output + ':' + change.split('=', 1)[0])
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        report(say, 'passthrough', 27, str(error))
        return 1


def show(say):
    try:
        objects = snapshot()
        choices = outputs(objects)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
        choices, objects = {}, []
    print(say(24))
    print(say(25))
    print(say(26))
    try:
        sinks = {sink['name']: sink for sink in pulse_sinks()}
    except (OSError, ValueError, subprocess.SubprocessError):
        sinks = {}
    for obj in objects:
        props = obj.get('info', {}).get('props', {})
        if props.get('media.class') == 'Audio/Sink' and not props.get('node.name', '').startswith('sparky.audio.'):
            name = props.get('node.name', '')
            options = choices.get(name, {})
            kind = say(32)
            if 'headphones' in options:
                kind = say(35 if options['headphones'] else 36)
            elif name in sinks:
                detected = headphone(sinks[name])
                kind += ' (' + say(39 if detected is None else (35 if detected else 36)) + ')'
            matrix = {'decode': 37, 'upmix': 38}.get(options.get('matrix'), 34)
            print(say(28, name, say(33 if options.get('enabled', True) else 34),
                      options.get('layout', say(32)), options.get('hrtf', 'MIT KEMAR'), kind, say(matrix)))
            if name in sinks:
                print(say(31, name, ' '.join(sorted(formats(sinks[name]))),
                          ' '.join(sorted(detected_codecs(sinks[name], objects)))))


def monitor(say):
    """Forward policy failures to the existing per-person problems engine.

    pw-dump -m emits consecutive JSON arrays, including the initial state.
    No shell text is built from an output name or imported file name.
    """
    process = subprocess.Popen(['pw-dump', '-m'], stdout=subprocess.PIPE)
    decoder = json.JSONDecoder()
    utf8 = codecs.getincrementaldecoder('utf-8')()
    buffer = ''
    previous = {}
    cache, last_codec, codec_notices = {}, {}, {}
    try:
        while chunk := process.stdout.read1(65536):
            buffer += utf8.decode(chunk)
            while buffer.strip():
                buffer = buffer.lstrip()
                try:
                    objects, end = decoder.raw_decode(buffer)
                except ValueError:
                    break
                buffer = buffer[end:]
                for obj in objects:
                    ident = obj.get('id')
                    if set(obj) == {'id'}:
                        cache.pop(ident, None)
                        last_codec.pop(ident, None)
                        continue
                    saved = cache.setdefault(ident, {})
                    for field, value in obj.items():
                        if field == 'info' and isinstance(value, dict):
                            saved.setdefault('info', {}).update(value)
                        else:
                            saved[field] = value
                    if obj.get('type') == 'PipeWire:Interface:Node':
                        for fmt in obj.get('info', {}).get('params', {}).get('Format', []):
                            if fmt.get('mediaSubtype') == 'iec958':
                                last_codec[ident] = fmt.get('iec958Codec', 'IEC61937')
                            elif fmt.get('mediaSubtype') == 'raw':
                                last_codec.pop(ident, None)
                for obj in cache.values():
                    if obj.get('type') != 'PipeWire:Interface:Link':
                        continue
                    info = obj.get('info', {})
                    fmt = info.get('format') or {}
                    if fmt.get('mediaSubtype') == 'iec958':
                        last_codec[info.get('input-node-id')] = fmt.get('iec958Codec', 'IEC61937')
                for ident, obj in list(cache.items()):
                    if obj.get('type') != 'PipeWire:Interface:Node' or ident not in last_codec:
                        continue
                    info = obj.get('info', {})
                    name = info.get('props', {}).get('node.name', '')
                    codec = str(last_codec[ident])
                    key = 'passthrough:' + name + ':' + codec
                    if info.get('state') == 'error':
                        detail = codec + ': ' + str(info.get('error', info['state']))
                        if codec_notices.get(key) != detail:
                            print(say(41, name, detail), flush=True)
                            subprocess.run(['sparky-stereo-problems', 'keep', 'sparky-stereo-audio', key,
                                            'LOCAL41', name, detail], check=True)
                            codec_notices[key] = detail
                    elif info.get('state') == 'running' and key in codec_notices:
                        subprocess.run(['sparky-stereo-problems', 'clear', 'sparky-stereo-audio', key], check=True)
                        codec_notices.pop(key)
                for obj in objects:
                    if obj.get('type') != 'PipeWire:Interface:Metadata':
                        continue
                    for entry in obj.get('metadata', []):
                        key = entry.get('key', '')
                        if not key.startswith('sparky.audio.problem.'):
                            continue
                        value = entry.get('value')
                        if key in previous and previous[key] == value:
                            continue
                        previous[key] = value
                        problem_key = 'surround:' + key.removeprefix('sparky.audio.problem.')
                        if value:
                            detail = '%s: %s' % (value.get('profile', ''), value.get('cause', ''))
                            number = 40 if value.get('cause') == 'output-type-unknown' else 27
                            detail = value.get('profile', '') if number == 40 else detail
                            print(say(number, detail), flush=True)
                            command = ['sparky-stereo-problems', 'keep', 'sparky-stereo-audio', problem_key, 'LOCAL%d' % number, detail]
                        else:
                            command = ['sparky-stereo-problems', 'clear', 'sparky-stereo-audio', problem_key]
                        subprocess.run(command, check=True)
        return process.wait()
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
