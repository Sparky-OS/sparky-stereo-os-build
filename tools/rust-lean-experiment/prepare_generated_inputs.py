#!/usr/bin/env python3
"""Capture Debian's original build-owned WIT literals before their prepared projection."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess


def prepare(source,work,output):
    producer='debian/scripts/build-wit-bindgen.sh'
    script=source/producer;digest=hashlib.sha256(script.read_bytes()).hexdigest()
    rules=(source/'debian/rules').read_text()
    paths=['vendor/wit-bindgen-0.57.1/src/rt','library/vendor/wit-bindgen-0.57.1/src/rt']
    for p in paths:
        if ('debian/scripts/build-wit-bindgen.sh 0.57.1 '+p) not in rules:
            raise RuntimeError('pinned WIT recipe changed: '+p)
    work.mkdir(parents=True,exist_ok=False);(work/'debian/scripts').mkdir(parents=True)
    shutil.copy2(script,work/producer)
    result={'scope':'original build-produced literals; form projections are separately token-qualified and bound in each source tree',
            'producer':producer,'producer_sha256':digest,'version':'0.57.1','files':{},'native_outputs':{}}
    for p in paths:
        (work/p).mkdir(parents=True)
        subprocess.run([producer,'0.57.1',p],cwd=work,check=True,env=dict(os.environ,LC_ALL='C',SOURCE_DATE_EPOCH='1794523022'))
        for artifact in sorted((work/p).iterdir()):
            data=artifact.read_bytes();name=artifact.relative_to(work).as_posix()
            row={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'lines':data.count(b'\n'),
                 'producer':producer,'producer_sha256':digest}
            if artifact.suffix=='.rs':result['files'][name]=row
            else:result['native_outputs'][name]=row
    if len(result['files'])!=2:raise RuntimeError('WIT generator did not produce exactly two Rust literals')
    output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PASS: two build-owned Rust literals and their original producer are bound; native outputs recorded')


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for n in ('source','work','output'):p.add_argument(n,type=Path)
    prepare(**vars(p.parse_args()))
