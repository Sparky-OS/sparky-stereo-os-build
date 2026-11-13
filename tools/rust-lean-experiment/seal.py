#!/usr/bin/env python3
"""Seal a prepared source tree and its full inventory for transport."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import tarfile
from prepare import inventory


def seal(source, destination, form, epoch):
    destination.mkdir(parents=True, exist_ok=True)
    manifest = inventory(source)
    (destination/(form+'.manifest.json')).write_text(json.dumps(manifest,sort_keys=True)+'\n')
    path = destination/(form+'.tar.gz')
    tmp = path.with_suffix('.partial')

    def normalized(info):
        info.uid = info.gid = 1000
        info.uname = info.gname = ''
        info.mtime = epoch
        info.pax_headers = {}
        return info

    with tmp.open('wb') as out:
        with gzip.GzipFile(filename='',mode='wb',fileobj=out,mtime=0,compresslevel=1) as gz:
            with tarfile.open(fileobj=gz,mode='w|') as tf:
                tf.add(source,arcname='.',filter=normalized)
    tmp.replace(path)
    digest=hashlib.file_digest(path.open('rb'),'sha256').hexdigest()
    result={'form':form,'tree_sha256':manifest['sha256'],'archive_sha256':digest,'archive_bytes':path.stat().st_size}
    (destination/(form+'.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('destination',type=Path)
    p.add_argument('form',choices=['A','B','C']);p.add_argument('epoch',type=int)
    a=p.parse_args();seal(a.source,a.destination,a.form,a.epoch)
