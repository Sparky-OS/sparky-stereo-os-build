#!/usr/bin/env python3
"""Bind final Rust inputs to lexer-qualified A/B/C bytes and build-led doc retentions."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile


def view(roots,archives,form,names):
    rows={};native=None
    def note(name,data):
        nonlocal native
        if name in names:rows[name]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'lines':data.count(b'\n')}
        if name=='.sparky-lc/source.json':
            report=json.loads(data);native={n:r for n,r in report['files'].items() if n.startswith('compiler/rustc_llvm/')}
    tree=roots/form
    if tree.is_dir():
        for name in names:note(name,(tree/name).read_bytes())
        note('.sparky-lc/source.json',(tree/'.sparky-lc/source.json').read_bytes())
    else:
        if archives is None:raise RuntimeError('source tree absent and no archive directory given: '+form)
        path=archives/(form+'.tar.gz');identity=json.loads((archives/(form+'.json')).read_text())
        with path.open('rb') as f:
            if hashlib.file_digest(f,'sha256').hexdigest()!=identity['archive_sha256']:raise RuntimeError('archive checksum mismatch: '+form)
        with tarfile.open(path,mode='r|gz') as tf:
            for m in tf:
                name=m.name.removeprefix('./')
                if name in names or name=='.sparky-lc/source.json':
                    stream=tf.extractfile(m)
                    if stream is None:raise RuntimeError('source is not a regular file: '+name)
                    note(name,stream.read())
    if set(rows)!=names or native is None:raise RuntimeError('source view incomplete: '+form)
    return rows,native


def verify(roots,ledger,exceptions,output,archives=None):
    source=json.loads(ledger.read_text());extra=json.loads(exceptions.read_text())
    authored={r['path']:r.get('sha256') for r in json.loads((ledger.parent/'A-manifest.json').read_text())['files']}
    restored={n for c in extra.values() for n in c['changed']}
    sums={f:{'files':0,'bytes':0,'lines':0} for f in 'ABC'};native={}
    for form in 'ABC':
        rows,native[form]=view(roots,archives,form,set(source['files']))
        for name,row in source['files'].items():
            target='B' if form=='C' and name in restored else form
            expected=row.get('sha256_'+target,authored[name])
            if rows[name]['sha256']!=expected:raise RuntimeError(f'final {form}/{name} differs from its lexer-qualified input')
            s=sums[form];s['files']+=1;s['bytes']+=rows[name]['bytes'];s['lines']+=rows[name]['lines']
    c_extra=sum(r.get('sha256_C')!=r.get('sha256_B') and n not in restored for n,r in source['files'].items())
    if native['A']!=native['B'] or native['B']!=native['C']:raise RuntimeError('native projections differ across forms')
    result={'Rust':sums,'additional_doc_removal_files_C':c_extra,'build_led_exceptions':extra,
            'static_doc_exceptions':source['C_doc_exceptions'],'lexer_scope':source['lexer'],
            'basis':'every final Rust file equals previously lexer-qualified A/B/C bytes; build-led retentions equal B',
            'native':native['A']}
    output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps(sums))


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for n in ('roots','ledger','exceptions','output'):p.add_argument(n,type=Path)
    p.add_argument('--archives',type=Path)
    verify(**vars(p.parse_args()))
