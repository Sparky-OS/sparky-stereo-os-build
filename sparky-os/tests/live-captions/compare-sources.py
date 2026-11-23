#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare every member of predecessor/successor source archives."""
import hashlib,json,sys,tarfile
from pathlib import Path
old,new,out=map(Path,sys.argv[1:4])
def members(path):
    result={}
    with tarfile.open(path) as archive:
        entries=archive.getmembers()
        roots={m.name.split('/')[0] for m in entries}
        strip=len(roots)==1 and next(iter(roots))!='debian'
        for member in entries:
            name=member.name.split('/',1)[1] if strip and '/' in member.name else member.name
            if strip and '/' not in member.name:continue
            stream=archive.extractfile(member) if member.isfile() else None
            result[name]=dict(type=member.type.decode(),mode=oct(member.mode),link=member.linkname,bytes=member.size,sha256=hashlib.sha256(stream.read()).hexdigest() if stream else None)
    return result
results=[]
for path in sorted(new.glob('*.tar.xz')):
    source=path.name.split('_')[0]
    suffix='.orig.tar.xz' if '.orig.tar.' in path.name else '.debian.tar.xz' if '.debian.tar.' in path.name else '.tar.xz'
    candidates=[p for p in old.glob(source+'_*'+suffix) if ('+lc' in p.name)==('+lc' in path.name)]
    assert len(candidates)==1,(path,candidates)
    a=members(candidates[0]);b=members(path)
    results.append(dict(before=candidates[0].name,after=path.name,files=[dict(path=p,before=a.get(p),after=b.get(p),status='same' if a.get(p)==b.get(p) else 'added' if p not in a else 'removed' if p not in b else 'changed') for p in sorted(a.keys()|b.keys())]))
out.write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps([dict(before=x['before'],after=x['after'],changed=[f['path'] for f in x['files'] if f['status']!='same']) for x in results],indent=2))
