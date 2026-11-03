#!/usr/bin/python3
"""The menu must retain every image/emulator/3D-role entry and use known packages."""
import json
from pathlib import Path
import sys
catalogue=Path(sys.argv[1])
lists=Path(sys.argv[2])
def lines(name):
    return [s.split('#')[0].strip() for s in (lists/name).read_text().splitlines() if s.split('#')[0].strip()]
rows=json.loads(catalogue.read_text())
known={s for name in ('image.list','apps.list','emulation-3d.list','gaming.list') for s in lines(name)}
known.update(s.split()[0] for s in lines('roles.tsv'))
known.add('vlc-stereo') # make-meta.py: OURS_PLAYER
packages={row['package'] for row in rows if row['kind']=='apt'}
assert packages <= known, packages-known
required=set(lines('image.list')+lines('emulation-3d.list'))
required.update(s.split()[0] for s in lines('roles.tsv') if s.split()[-1]=='3d')
assert required <= packages, required-packages
assert {row['package'] for row in rows if row['section']=='emulation'}==set(lines('emulation-3d.list'))
assert len({row['id'] for row in rows})==len(rows)
print(f'PASS {len(rows)} entries; required lists covered; no unknown package')
