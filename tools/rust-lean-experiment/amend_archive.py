#!/usr/bin/env python3
"""Replace one reviewed preparation file, then rebind a source transport identity."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile


def amend(directory,form,name,payload):
    if Path(name).is_absolute() or '..' in Path(name).parts:raise ValueError('unsafe source-relative name')
    archive=directory/(form+'.tar.gz');manifest_path=directory/(form+'.manifest.json');identity_path=directory/(form+'.json')
    identity=json.loads(identity_path.read_text());manifest=json.loads(manifest_path.read_text())
    with archive.open('rb') as f:
        if hashlib.file_digest(f,'sha256').hexdigest()!=identity['archive_sha256']:raise RuntimeError('old archive identity mismatch')
    matches=[r for r in manifest['files'] if r['path']==name]
    if len(matches)!=1 or 'sha256' not in matches[0]:raise RuntimeError('replacement is not one manifested regular file')
    row=matches[0];new=payload.read_bytes();count=0;temporary=archive.with_suffix('.amend-partial')
    with archive.open('rb') as source,temporary.open('wb') as dest:
        with tarfile.open(fileobj=source,mode='r|gz') as old,gzip.GzipFile(filename='',mode='wb',fileobj=dest,mtime=0,compresslevel=1) as gz:
            with tarfile.open(fileobj=gz,mode='w|') as target:
                for member in old:
                    stream=old.extractfile(member) if member.isfile() else None
                    if member.name.removeprefix('./')==name:
                        data=stream.read()
                        if hashlib.sha256(data).hexdigest()!=row['sha256']:raise RuntimeError('old member differs from manifest')
                        member.size=len(new);stream=io.BytesIO(new);count+=1
                    target.addfile(member,stream)
    if count!=1:raise RuntimeError('archive replacement count is not one')
    old_identity=dict(identity);row.update(bytes=len(new),sha256=hashlib.sha256(new).hexdigest())
    manifest['bytes']=sum(r.get('bytes',0) for r in manifest['files'])
    manifest['sha256']=hashlib.sha256(json.dumps(manifest['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
    identity.update(tree_sha256=manifest['sha256'],archive_bytes=temporary.stat().st_size)
    with temporary.open('rb') as f:identity['archive_sha256']=hashlib.file_digest(f,'sha256').hexdigest()
    temporary.replace(archive)
    manifest_path.write_text(json.dumps(manifest,sort_keys=True)+'\n');identity_path.write_text(json.dumps(identity,indent=2)+'\n')
    print(json.dumps({'form':form,'member':name,'old':old_identity,'new':identity}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('form');p.add_argument('name');p.add_argument('payload',type=Path)
    amend(**vars(p.parse_args()))
