#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare every control and payload member of each successor with its predecessor."""
import hashlib,io,json,subprocess,sys,tarfile
from pathlib import Path
old,new,out=map(Path,sys.argv[1:4]);out.mkdir(parents=True,exist_ok=False)
def members(deb,control=False):
    data=subprocess.check_output(['dpkg-deb','--ctrl-tarfile' if control else '--fsys-tarfile',str(deb)])
    result={}
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for entry in archive:
            stream=archive.extractfile(entry) if entry.isfile() else None
            result[entry.name]=dict(kind=entry.type.decode(),mode=oct(entry.mode),uid=entry.uid,gid=entry.gid,size=entry.size,link=entry.linkname,sha256=hashlib.sha256(stream.read()).hexdigest() if stream else None)
    return result
summary=[]
for deb in sorted(new.glob('*.deb')):
    package=deb.name.split('_')[0];previous=list(old.glob(package+'_*.deb'));assert len(previous)==1,(package,previous)
    details={};counts={}
    for kind in ('control','payload'):
        a=members(previous[0],kind=='control');b=members(deb,kind=='control')
        details[kind]=[dict(path=p,before=a.get(p),after=b.get(p),status='same' if a.get(p)==b.get(p) else 'added' if p not in a else 'removed' if p not in b else 'changed') for p in sorted(a.keys()|b.keys())]
        counts[kind]={state:sum(x['status']==state for x in details[kind]) for state in ('same','changed','added','removed')}
    (out/(package+'.json')).write_text(json.dumps(details,indent=2)+'\n')
    summary.append(dict(package=package,before=previous[0].name,after=deb.name,counts=counts))
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
