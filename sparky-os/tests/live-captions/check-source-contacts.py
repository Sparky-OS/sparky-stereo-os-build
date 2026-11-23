#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check our DEP-5 files in authored and Lean source closures, never upstream orig."""
import json,re,sys,tarfile
from pathlib import Path
rows=[]
for path in sorted(Path(sys.argv[1]).glob('*.debian.tar.xz')):
    if path.name.split('_')[0] not in ('captiond','kaption'):continue
    with tarfile.open(path) as archive:
        member=next(m for m in archive if m.name.lstrip('./')=='debian/copyright')
        for line,text in enumerate(archive.extractfile(member).read().decode().splitlines(),1):
            for match in re.findall(r'[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',text):
                allowed=match=='Capitain_Jack@yahoo.com'
                rows.append(dict(archive=path.name,file='debian/copyright',line=line,match=match if allowed else '[third-party contact]',passed=allowed))
print(json.dumps(rows,indent=2))
sys.exit(0 if all(r['passed'] for r in rows) else 1)
