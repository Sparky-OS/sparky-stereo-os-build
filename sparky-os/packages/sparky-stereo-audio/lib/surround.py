# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Graph descriptions for the audio engine; no device is opened here.

PipeWire's SOFA spatializer and convolution examples own the processing.
HeSuVi channel indices follow PipeWire's sink-virtual-surround-7.1-hesuvi.conf.
"""
import json
import os
import re

KEMAR = '/usr/share/libmysofa/MIT_KEMAR_normal_pinna.sofa'
LAYOUTS = {'5.1': ['FL', 'FR', 'FC', 'LFE', 'SL', 'SR'],
           '7.1': ['FL', 'FR', 'FC', 'LFE', 'RL', 'RR', 'SL', 'SR']}
# ITU-R BS.775 horizontal layout, SOFA azimuth positive to the listener's left.
ANGLES = {'FL': 30, 'FR': 330, 'FC': 0, 'LFE': 0,
          'SL': 110, 'SR': 250, 'RL': 150, 'RR': 210}
HESUVI = {'FL': (0, 1), 'FR': (8, 7), 'FC': (6, 13), 'LFE': (6, 13),
          'SL': (2, 3), 'SR': (10, 9), 'RL': (4, 5), 'RR': (12, 11)}
SAD_CODECS = {2: 'AC3', 7: 'DTS', 10: 'EAC3', 11: 'DTSHD', 12: 'TRUEHD'}


def eld_formats(text):
    """Read only valid, connected ELDs. Codes come from CTA-861 SADs.

    Linux sound/core/eld.c prints sadN_coding_type; no monitor-name matching
    and no union across outputs is safe for enabling passthrough.
    """
    if not text or not all(re.search(r'^' + k + r'\s+1\s*$', text, re.M)
                           for k in ('monitor_present', 'eld_valid')):
        return []
    count = re.search(r'^sad_count\s+(\d+)\s*$', text, re.M)
    if not count or not 0 <= int(count[1]) <= 15:
        return []
    formats = set()
    for i in range(int(count[1])):
        m = re.search(r'^sad%d_coding_type\s+\[0x([0-9a-fA-F]+)\]' % i, text, re.M)
        if m and int(m[1], 16) in SAD_CODECS:
            formats.add(SAD_CODECS[int(m[1], 16)])
    return sorted(formats)


def headphone(sink):
    """Use the active port and authoritative Bluetooth form factor/profile.

    A2DP, USB and a stereo channel map by themselves also describe speakers.
    pactl JSON exposes the active ALSA port's type, including headphones.
    """
    props = sink.get('properties', {})
    active = sink.get('active_port')
    ports = sink.get('ports', [])
    if isinstance(ports, dict):
        ports = [dict(value, name=key) for key, value in ports.items()]
    for port in ports:
        if port.get('name') == active:
            return str(port.get('type', '')).lower() in ('headphones', 'headset')
    form = str(props.get('device.form_factor', props.get('device.form-factor', '')))
    icon = str(props.get('device.icon_name', props.get('api.bluez5.icon', '')))
    profile = str(props.get('api.bluez5.profile', props.get('bluez5.profile', '')))
    return (form in ('headphone', 'headphones', 'headset') or
            icon in ('audio-headphones', 'audio-headset') or
            profile in ('headset-head-unit', 'headset-head-unit-cvsd',
                        'headset-head-unit-msbc', 'hfp-hf', 'hsp-hs'))


def binaural(layout, filename=KEMAR, kind='sofa'):
    positions = LAYOUTS[layout]
    nodes, links, inputs = [], [], []
    for index, channel in enumerate(positions, 1):
        if kind == 'sofa':
            nodes.append({'type': 'sofa', 'name': channel, 'label': 'spatializer',
                          'config': {'filename': filename},
                          'control': {'Azimuth': ANGLES[channel], 'Elevation': 0, 'Radius': 1.4}})
            inputs.append(channel + ':In')
            for ear in ('L', 'R'):
                links.append({'output': channel + ':Out ' + ear, 'input': 'mix' + ear + ':In ' + str(index)})
        elif kind == 'hesuvi':
            copy = 'copy' + channel
            nodes.append({'type': 'builtin', 'name': copy, 'label': 'copy'})
            inputs.append(copy + ':In')
            for ear, wav_channel in zip(('L', 'R'), HESUVI[channel]):
                name = channel + ear
                nodes.append({'type': 'builtin', 'name': name, 'label': 'convolver',
                              'config': {'filename': filename, 'channel': wav_channel}})
                links.append({'output': copy + ':Out', 'input': name + ':In'})
                links.append({'output': name + ':Out', 'input': 'mix' + ear + ':In ' + str(index)})
        else:
            raise ValueError('hrtf type')
    nodes += [{'type': 'builtin', 'name': 'mix' + ear, 'label': 'mixer'} for ear in ('L', 'R')]
    return {'nodes': nodes, 'links': links, 'inputs': inputs, 'outputs': ['mixL:Out', 'mixR:Out']}


def module_args(name, target, graph, positions, description):
    """No audio.rate/node.rate: response data is resampled at the graph rate.

    The owner removes the whole client context at teardown. Linger protects
    a dont-fallback stream while its target is briefly missing.
    """
    return {'node.description': description, 'media.name': description, 'filter.graph': graph,
            'capture.props': {'node.name': name, 'media.class': 'Audio/Sink',
                              'node.virtual': True, 'priority.session': 0,
                              'audio.channels': len(positions), 'audio.position': positions},
            'playback.props': {'node.name': name + '.output', 'node.passive': True,
                               'node.dont-fallback': True, 'node.linger': True,
                               'target.object': target, 'stream.dont-remix': True,
                               'audio.channels': 2, 'audio.position': ['FL', 'FR']}}


def client_config(args):
    return {'context.spa-libs': {'audio.convert.*': 'audioconvert/libspa-audioconvert',
                                 'support.*': 'support/libspa-support'},
            'context.modules': [{'name': name} for name in
                                ('libpipewire-module-protocol-native', 'libpipewire-module-client-node',
                                 'libpipewire-module-adapter')] +
                               [{'name': 'libpipewire-module-filter-chain', 'args': args}]}
