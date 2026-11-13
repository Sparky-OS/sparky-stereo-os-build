#!/usr/bin/env python3
"""Bind final Rust inputs to already lexer-qualified A/B/C bytes and doc retentions."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(roots,ledger,exceptions,output):
    source=json.loads(ledger.read_text());extra=json.loads(exceptions.read_text())
    authored={r['path']:r.get('sha256') for r in json.loads((ledger.parent/'A-manifest.json').read_text())['files']}
    restored={n for c in extra.values() for n in c['changed']}
    sums={f:{'files':0,'bytes':0,'lines':0} for f in 'ABC'}
    c_extra=0
    for name,row in source['files'].items():
        for form in 'ABC':
            data=(roots/form/name).read_bytes()
            target='B' if form=='C' and name in restored else form
            expected=row.get('sha256_'+target,row.get('sha256'))
            if expected is None:
                expected=authored[name]
            if hashlib.sha256(data).hexdigest()!=expected:
                raise RuntimeError(f'final {form}/{name} differs from its lexer-qualified input')
            s=sums[form];s['files']+=1;s['bytes']+=len(data);s['lines']+=data.count(b'\n')
        if row.get('sha256_C')!=row.get('sha256_B') and name not in restored:c_extra+=1
    native={}
    for f in 'ABC':
        report=json.loads((roots/f/'.sparky-lc/source.json').read_text())
        native[f]={n:r for n,r in report['files'].items() if n.startswith('compiler/rustc_llvm/')}
    if native['A']!=native['B'] or native['B']!=native['C']:
        raise RuntimeError('native projections differ across forms')
    result={'Rust':sums,'additional_doc_removal_files_C':c_extra,'build_led_exceptions':extra,
            'static_doc_exceptions':source['C_doc_exceptions'],'lexer_scope':source['lexer'],
            'basis':'every final Rust file equals its previously lexer-qualified A/B/C bytes; build-led retentions equal B',
            'native':native['A']}
    output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps(sums))


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for n in ('roots','ledger','exceptions','output'):p.add_argument(n,type=Path)
    verify(**vars(p.parse_args()))
