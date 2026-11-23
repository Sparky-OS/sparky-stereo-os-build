#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""An upgrade of the fixture cohort must never silently remove another member."""
import json,sys
from pathlib import Path
def check(lines,expected):
    removed=[line for line in lines if line.startswith('Remv ')]
    installed=[line for line in lines if line.startswith('Inst ')]
    if removed:raise ValueError('Upgrade would remove installed packages: '+ '; '.join(removed))
    found=[line.split()[1] for line in installed]
    if set(found)!=set(expected) or len(found)!=len(expected):raise ValueError('Unexpected Inst set: '+repr(found)+'; expected '+repr(expected))
    return dict(Inst=installed,Remv=removed)
if __name__=='__main__':
    try:print(json.dumps(check(Path(sys.argv[1]).read_text().splitlines(),json.loads(Path(sys.argv[2]).read_text())),indent=2))
    except ValueError as error:print(str(error),file=sys.stderr);raise SystemExit(1)
