#!/usr/bin/env python3
# Copyright 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build projected source with the exact compiler that qualified its Zig tokens."""
import os
from pathlib import Path
import shlex
import subprocess
import sys

source = Path(sys.argv[1]).resolve()
compiler = source / 'build/consumer/bin/zig'
if os.environ.get('LEAN_ZIG') != str(compiler) or not compiler.is_file():
    sys.exit('cgm-zig: final build requires its full source-built Lean consumer')
commands = source / 'build/stage3-commands.txt'
checker = source / 'debian/cgm/check-stage3-command.py'
subprocess.run([sys.executable, str(checker), str(commands)], check=True)
rows = [shlex.split(line) for line in commands.read_text().splitlines() if 'zig2 build ' in line]
if len(rows) != 1 or rows[0][:4] != ['cd', str(source), '&&', str(source / 'build/zig2')]:
    sys.exit('cgm-zig: unexpected CMake command shape; review final build integration')
args = [str(compiler), *rows[0][4:]]
actual = source / 'build/final-command.txt'
actual.write_text(shlex.join(args) + '\n')
subprocess.run([sys.executable, str(checker), str(actual)], check=True)
print(shlex.join(args), flush=True)
subprocess.run(args, cwd=source, check=True)
