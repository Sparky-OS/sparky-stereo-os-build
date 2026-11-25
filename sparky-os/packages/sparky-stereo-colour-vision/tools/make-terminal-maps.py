#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Write the terminal maps from tools/terminal-maps.json: data/BreezeColourVisionKIND.colorscheme (Konsole's Breeze with the
kind's entries, every other line as Konsole has it) and data/console-KIND.palette (the Linux console's 16 colours, for
ESC ] P n rrggbb). Usage: make-terminal-maps.py KONSOLE_BREEZE.colorscheme [DATA_DIR]"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
maps = json.loads((HERE / 'terminal-maps.json').read_text())
breeze = Path(sys.argv[1]).read_text().splitlines()
data = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE.parent / 'data'

KIND_NAMES = {'protan': 'Protan', 'deutan': 'Deutan', 'tritan': 'Tritan', 'mono': 'Mono'}
for kind, entries in maps['konsole_by_kind'].items():
    out, group = [], None
    for line in breeze:
        if line.startswith('[') and line.endswith(']'):
            group = line[1:-1]
        elif group in entries and line.startswith('Color='):
            line = 'Color=' + ','.join(str(c) for c in entries[group])
        elif group == 'General' and line.startswith('Description='):
            out.append(f"Description={maps['konsole_name']['en']} ({KIND_NAMES[kind]})")
            out.extend(f'Description[{lang}]={name} ({KIND_NAMES[kind]})' for lang, name in sorted(maps['konsole_name'].items()) if lang != 'en')
            continue
        elif group == 'General' and line.startswith('Description['):
            continue
        out.append(line)
    (data / f'BreezeColourVision{KIND_NAMES[kind]}.colorscheme').write_text('\n'.join(out) + '\n')

vga = maps['vga']
for kind, entries in maps['console'].items():
    palette = dict((int(k), v) for k, v in vga.items())
    palette.update((int(k), v) for k, v in entries.items())
    (data / f'console-{kind}.palette').write_text(
        ''.join(f'{i} {c[0]:02x}{c[1]:02x}{c[2]:02x}\n' for i, c in sorted(palette.items())))
print('written', data)
