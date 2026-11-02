#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the actual generated self-hosted command, not CMake cache labels."""
import pathlib
import shlex
import sys

commands = pathlib.Path(sys.argv[1]).read_text().splitlines()
parsed = [shlex.split(line) for line in commands]
rows = [args for args in parsed if any(pathlib.Path(a).name in ('zig', 'zig2') and args[i + 1:i + 2] == ['build'] for i, a in enumerate(args))]
if len(rows) != 1:
    sys.exit(f'cgm-zig: expected one stage3 command, found {len(rows)}')
args = rows[0]
required = {'-Doptimize=ReleaseSafe', '-Ddebug-extensions', '-j4',
            '-Dcpu=baseline', '-Dversion-string=0.16.0+cgm.0399d2b19b'}
missing = required - set(args)
forbidden = {'-Dstrip', '-Dstrip=true', '-Doptimize=ReleaseFast'} & set(args)
if missing or forbidden:
    sys.exit(f'cgm-zig: invalid stage3 command: missing={sorted(missing)}, forbidden={sorted(forbidden)}')
print('cgm-zig: stage3 command has ReleaseSafe, debug extensions, baseline CPU, four jobs and pinned version')
