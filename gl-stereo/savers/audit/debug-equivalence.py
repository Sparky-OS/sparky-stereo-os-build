#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Allow only nonloaded GNU debug-link bytes to differ across a rebuild."""
import hashlib
import json
from pathlib import Path
import struct
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def equivalent(before, after):
    if len(before) != len(after) or before[:7] != b'\x7fELF\x02\x01\x01':
        return False
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', before)
    phoff, shoff = header[5:7]
    phsize, phcount, shsize, shcount, namesindex = header[9:14]
    if phsize != 56 or shsize != 64:
        return False
    sections = [struct.unpack_from('<IIQQQQIIQQ', before, shoff + i * shsize) for i in range(shcount)]
    names = sections[namesindex]
    strings = before[names[4]:names[4] + names[5]]
    loads = []
    for i in range(phcount):
        segment = struct.unpack_from('<IIQQQQQQ', before, phoff + i * phsize)
        if segment[0] == 1:
            loads.append((segment[2], segment[2] + segment[5]))
    first, second = bytearray(before), bytearray(after)
    for section in sections:
        name = strings[section[0]:].split(b'\0', 1)[0]
        if name not in (b'.gnu_debugaltlink', b'.gnu_debuglink'):
            continue
        start, end = section[4], section[4] + section[5]
        if section[2] & 2 or any(start < high and end > low for low, high in loads):
            return False
        if end > len(before):
            return False
        first[start:end] = second[start:end] = bytes(end - start)
    return first == second


if __name__ == '__main__':
    old = Path(sys.argv[1]); inventory = json.loads(Path(sys.argv[2]).read_text())
    results = {}
    for entry in inventory:
        if entry['kind'] != 'hack':
            continue
        name = entry['id']; before = (old/name).read_bytes()
        after = (Path('/usr/libexec/xscreensaver')/name).read_bytes()
        if before == after:
            continue
        if name == 'flurry':
            assert not equivalent(before, after), 'owning camera fix must change runtime bytes'
            continue
        assert equivalent(before, after), (name, 'runtime bytes changed; new captures required')
        # Changes to executable bytes and ELF headers must fail the same gate.
        mutant = bytearray(after); mutant[0] ^= 1
        assert not equivalent(before, mutant)
        header = struct.unpack_from('<16sHHIQQQIHHHHHH', after)
        sections = [struct.unpack_from('<IIQQQQIIQQ', after, header[6] + i*64) for i in range(header[12])]
        executable = next(section for section in sections if section[2] & 4 and section[5])
        mutant = bytearray(after); mutant[executable[4]] ^= 1
        assert not equivalent(before, mutant)
        results[name] = dict(tested_sha256=digest(before), installed_sha256=digest(after),
                             permitted_difference='nonloaded GNU debug links only')
    Path(sys.argv[3]).write_text(json.dumps(results, indent=2)+'\n')
    print('PASS:', len(results), 'debug-metadata-only changes; all other bytes identical; ELF-header and executable-byte mutations rejected')
