# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Candidate argv match for Vinci Resolve launchers; deliberately not enabled.

A rootless Ubuntu 24.04 distrobox CUDA/GL probe passed with the edition's
inherited zink settings. A host exception is not required by that measurement.
If a future distrobox version preserves those vendor overrides, match the
specific inner application, never every program run by distrobox.
"""
from pathlib import PurePosixPath
import re
import shlex


def is_vinci_resolve(command):
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    if len(words) < 7 or PurePosixPath(words[0]).name != 'distrobox':
        return False
    if words[1:3] != ['enter', '--name'] or words[3] not in ('vinci-free', 'vinci-studio'):
        return False
    if words[4:6] != ['--', 'env']:
        return False
    index = 6
    while index < len(words) and re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*=.*', words[index]):
        index += 1
    return index < len(words) and words[index] == '/opt/resolve/bin/resolve'


if __name__ == '__main__':
    prefix = '/usr/bin/distrobox enter --name vinci-free -- env '
    cases = {
        prefix + 'QT_QPA_PLATFORM=xcb __GLX_VENDOR_LIBRARY_NAME=nvidia /opt/resolve/bin/resolve %f': True,
        prefix.replace('vinci-free', 'vinci-studio') + '/opt/resolve/bin/resolve': True,
        prefix.replace('/usr/bin/distrobox', '"/home/test/.local/share/vinci/distrobox"') + '/opt/resolve/bin/resolve': True,
        prefix.replace('vinci-free', 'other') + '/opt/resolve/bin/resolve': False,
        prefix + '/bin/sh -c /opt/resolve/bin/resolve': False,
        prefix + '/opt/resolve/bin/resolve-other': False,
        prefix.replace('distrobox', 'distrobox-host-exec') + '/opt/resolve/bin/resolve': False,
        prefix.replace('--name vinci-free', '--name vinci-free-other') + '/opt/resolve/bin/resolve': False,
        prefix.replace('-- env', '--') + '/opt/resolve/bin/resolve': False,
        '/usr/bin/resolve': False,
        prefix + '"': False,
    }
    for command, expected in cases.items():
        assert is_vinci_resolve(command) == expected, command
    print(f'Vinci launcher proposal: {len(cases)} cases passed; no default changed')
