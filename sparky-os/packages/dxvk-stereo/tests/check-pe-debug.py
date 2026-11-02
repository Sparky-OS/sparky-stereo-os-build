#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate the identity and CRC of DXVK's separate Windows debug files."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zlib


def inspect(dll, debug_root, readobj, objdump):
    errors = []
    text = subprocess.check_output([readobj, '--coff-debug-directory', str(dll)], text=True)
    matches = re.findall(r'^\s*PDBGUID:\s*(.+)$', text, re.M)
    build_id = re.sub('[^0-9A-F]', '', matches[0]) if len(matches) == 1 else ''
    if len(build_id) != 32:
        errors.append('missing or malformed CodeView build ID')
    dump = subprocess.check_output([objdump, '-s', '-j', '.gnu_debuglink', str(dll)], text=True)
    groups = re.findall(r'^\s+[0-9a-fA-F]+\s+((?:[0-9a-fA-F]{8}\s+){1,4})', dump, re.M)
    data = bytes.fromhex(''.join(''.join(x.split()) for x in groups))
    name, separator, _ = data.partition(b'\0')
    offset = (len(name) + 4) & ~3
    if not separator or offset + 4 != len(data):
        raise ValueError(f'{dll}: malformed .gnu_debuglink')
    name = name.decode('ascii')
    expected_crc = struct.unpack_from('<I', data, offset)[0]
    expected_name = build_id[2:] + '.debug'
    if name != expected_name or name == '.debug':
        errors.append('debug link does not identify a unique build-ID file')
    debug = debug_root / build_id[:2] / expected_name
    crc = 0
    digest = hashlib.sha256()
    if not debug.is_file():
        errors.append('separate debug file is absent')
    else:
        with debug.open('rb') as stream:
            while block := stream.read(1024 * 1024):
                crc = zlib.crc32(block, crc)
                digest.update(block)
        if crc != expected_crc:
            errors.append('separate debug file CRC differs from .gnu_debuglink')
    return {'dll': str(dll), 'build_id': build_id, 'debug_link': name,
            'debug_file': str(debug), 'expected_crc32': expected_crc,
            'actual_crc32': crc, 'debug_sha256': digest.hexdigest(), 'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dll_directory', type=Path)
    parser.add_argument('debug_build_id_directory', type=Path)
    parser.add_argument('--readobj', default='llvm-readobj')
    parser.add_argument('--objdump', default='x86_64-w64-mingw32-objdump')
    parser.add_argument('--expected-count', type=int, default=5)
    args = parser.parse_args()
    rows = [inspect(p, args.debug_build_id_directory, args.readobj, args.objdump)
            for p in sorted(args.dll_directory.glob('*.dll.so'))]
    ids = [r['build_id'] for r in rows]
    valid = (len(rows) == args.expected_count and len(set(ids)) == len(ids)
             and not any(r['errors'] for r in rows))
    print(json.dumps({'status': 'PASS' if valid else 'FAIL', 'dlls': rows,
                      'expected_count': args.expected_count,
                      'distinct_build_ids': len(set(ids))}, indent=2))
    return 0 if valid else 1


if __name__ == '__main__':
    raise SystemExit(main())
