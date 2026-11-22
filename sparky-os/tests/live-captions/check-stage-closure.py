#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every staged regular file, including hidden metadata, must be summed."""
import hashlib,json,sys
from pathlib import Path
stage=Path(sys.argv[1]);listed={}
for line in (stage/'SHA256SUMS').read_text().splitlines():
    sha,name=line.split(None,1);name=name.lstrip('* ')
    assert name not in listed,'duplicate checksum '+name
    listed[name]=sha
actual={str(p.relative_to(stage)):p for p in stage.rglob('*') if p.is_file() and p.name!='SHA256SUMS'}
assert set(actual)==set(listed),dict(unlisted=sorted(actual.keys()-listed.keys()),missing=sorted(listed.keys()-actual.keys()))
for name,path in actual.items():
    assert not path.is_symlink() and path.resolve().is_relative_to(stage.resolve()),name
    with path.open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==listed[name],name
records=[]
for p in stage.glob('*.sparky-build.json'):
    data=json.loads(p.read_text());assert data['recipeDirty'] is False and data['unrecorded']==[]
    records.append(dict(source=data['source'],version=data['version'],commit=data['recipeCommit']))
assert len(records)==4,records
# A .dsc names its complete source closure; both original and lc forms are kept.
for p in stage.glob('*.dsc'):
    body=p.read_text();in_sums=False
    for line in body.splitlines():
        if line=='Checksums-Sha256:':in_sums=True;continue
        if in_sums and not line.startswith(' '):break
        if in_sums:
            sha,size,name=line.split();assert name in listed and listed[name]==sha and actual[name].stat().st_size==int(size)
print(json.dumps(dict(files=len(listed),hidden=[n for n in listed if n.startswith('.')],records=records),indent=2))
