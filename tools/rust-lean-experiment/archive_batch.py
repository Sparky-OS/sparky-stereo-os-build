#!/usr/bin/env python3
"""Apply reviewed preparation metadata/assets to an archive and rebind its manifest."""
import argparse,gzip,hashlib,io,json,tarfile
from pathlib import Path


def apply(directory,form,patches):
    archive=directory/(form+'.tar.gz');mp=directory/(form+'.manifest.json');ip=directory/(form+'.json')
    manifest=json.loads(mp.read_text());identity=json.loads(ip.read_text());rows={r['path']:r for r in manifest['files']}
    with archive.open('rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=identity['archive_sha256']:raise RuntimeError('archive identity changed')
    changes={n:(p.read_bytes(),mode) for n,p,mode in patches}
    if any(Path(n).is_absolute() or '..' in Path(n).parts for n in changes):raise ValueError('unsafe patch path')
    seen=set();temp=archive.with_suffix('.batch-partial')
    with tarfile.open(archive,mode='r|gz') as source,temp.open('wb') as raw,gzip.GzipFile(fileobj=raw,filename='',mode='wb',mtime=0,compresslevel=1) as gz,tarfile.open(fileobj=gz,mode='w|') as out:
        for m in source:
            name=m.name.removeprefix('./');stream=source.extractfile(m) if m.isfile() else None
            if name in changes:
                old=stream.read()
                if hashlib.sha256(old).hexdigest()!=rows[name]['sha256']:raise RuntimeError('member differs from manifest: '+name)
                data,mode=changes[name];m.size=len(data);m.mode=mode;stream=io.BytesIO(data);seen.add(name)
            out.addfile(m,stream)
        for name,(data,mode) in changes.items():
            if name not in seen:
                m=tarfile.TarInfo('./'+name);m.size=len(data);m.mode=mode;m.uid=m.gid=1000;m.mtime=1794523022
                out.addfile(m,io.BytesIO(data))
            rows[name]={'path':name,'mode':mode,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    manifest['files']=sorted(rows.values(),key=lambda r:r['path']);manifest['bytes']=sum(r.get('bytes',0) for r in rows.values())
    manifest['sha256']=hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    old=dict(identity);identity.update(tree_sha256=manifest['sha256'],archive_bytes=temp.stat().st_size)
    with temp.open('rb') as f:identity['archive_sha256']=hashlib.file_digest(f,'sha256').hexdigest()
    temp.replace(archive);mp.write_text(json.dumps(manifest,sort_keys=True)+'\n');ip.write_text(json.dumps(identity,indent=2)+'\n')
    print(json.dumps({'form':form,'old':old,'new':identity,'patched':sorted(changes)}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('form');p.add_argument('patchlist',type=Path);a=p.parse_args()
    apply(a.directory,a.form,[(n,Path(f),mode) for n,f,mode in json.loads(a.patchlist.read_text())])
