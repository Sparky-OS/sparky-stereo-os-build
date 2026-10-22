#!/usr/bin/env python3
"""Compare exact upstream archives with the retained accepted browser compilers."""
from pathlib import Path
import hashlib,json,os,subprocess,tarfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
b=(cfg.path('SPARKY_MIGRATION_WORK') / 'browser-source')
manifest=json.loads((b/'source/debian/toolchain-manifest.json').read_text())['files']
reports={}
for name,prefix,archive in [('clang','.mozbuild/clang-22','clang.tar.zst'),('wasi','.mozbuild/sysroot-wasm32-wasi','sysroot-wasm32-wasi.tar.zst')]:
    inventory={}
    proc=subprocess.Popen(['zstd','-dc',str(b/'accepted-toolchain-downloads'/archive)],stdout=subprocess.PIPE)
    with tarfile.open(fileobj=proc.stdout,mode='r|') as stream:
        for member in stream:
            rel=Path(member.name).parts[1:]
            if not rel or member.isdir():continue
            target=str(Path(prefix).joinpath(*rel))
            if member.issym():record={'kind':'symlink','target':member.linkname}
            elif member.isfile():
                content=stream.extractfile(member)
                record={'kind':'file','sha256':hashlib.file_digest(content,'sha256').hexdigest(),'mode':member.mode & 0o777}
            else:raise ValueError(('Unexpected archive member',member.name,member.type))
            inventory[target]=record
    assert proc.wait()==0
    # Exact aliases made by the accepted fetch-clang-22.sh, not changed compiler bytes.
    aliases={}
    if name=='clang':
        for path,row in list(inventory.items()):
            if path.endswith('/lib/wasi/libclang_rt.builtins-wasm32.a'):
                aliases[path.replace('/wasi/libclang_rt.builtins-wasm32.a','/wasm32-unknown-wasip1/libclang_rt.builtins.a')]=row
    else:
        for folder in ['lib','share','include']:
            for old,new in [('wasm32-wasi','wasm32-wasip1'),('wasm32-wasi-threads','wasm32-wasip1-threads')]:
                if folder=='include' and old.endswith('-threads'):continue
                oldprefix=f'{prefix}/{folder}/{old}/';newprefix=f'{prefix}/{folder}/{new}/'
                for path,row in list(inventory.items()):
                    if path.startswith(oldprefix):aliases[newprefix+path[len(oldprefix):]]=row
    inventory.update(aliases)
    expected={p:r for p,r in manifest.items() if p.startswith(prefix+'/')}
    differences=[p for p in inventory.keys() & expected.keys() if inventory[p]!=expected[p]]
    report={'archive':archive,'archive_sha256':hashlib.file_digest((b/'accepted-toolchain-downloads'/archive).open('rb'),'sha256').hexdigest(),'members':len(inventory),'aliases':len(aliases),'differences':sorted(differences),'missing':sorted(expected.keys()-inventory.keys()),'extra':sorted(inventory.keys()-expected.keys())}
    report['passed']=not any(report[x] for x in ['differences','missing','extra']);reports[name]=report
    print(name,{k:(len(v) if isinstance(v,list) else v) for k,v in report.items()},flush=True)
(b/'accepted-toolchain-downloads/comparison.json').write_text(json.dumps(reports,indent=2)+'\n')
assert all(r['passed'] for r in reports.values())
