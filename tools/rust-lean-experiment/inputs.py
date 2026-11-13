#!/usr/bin/env python3
"""Census of unique Rust source inputs named by actual compiler dep-info."""
import hashlib
import json
from pathlib import Path
import re
import tomllib


def census(tree, output, reference=None, generated_spec=None):
    if generated_spec is None:
        spec=Path(__file__).with_name('generated-source-inputs.json')
        generated_spec=json.loads(spec.read_text()) if spec.is_file() else {'files':{}}
    if reference is not None and (reference/'debian/sparky-wit-projection.json').is_file():
        generated_spec=json.loads((reference/'debian/sparky-wit-projection.json').read_text())
    names, depfiles = set(), 0
    for p in (tree/'build').rglob('*.d'):
        if not p.is_file():continue
        depfiles += 1
        text=p.read_text(errors='strict').replace('\\\n','')
        # Rust's generated dep-info uses Make backslash quoting, including spaces.
        for line in text.splitlines():
            if not line or line.startswith('#') or ': ' not in line: continue
            rhs=line.split(': ',1)[1]
            for token in re.findall(r'(?:\\.|[^\s])+',rhs):
                token=re.sub(r'\\(.)',r'\1',token)
                if token.endswith('.rs'): names.add((token,p))
    if not depfiles or not names: raise RuntimeError('build produced no Rust dep-info inputs')
    rows={}
    for name,depfile in sorted(names):
        p=Path(name)
        if not p.is_absolute():
            p=tree/p
            if not p.is_file():
                # Cargo's nested proc-macro-test build emits crate-relative
                # dep-info. Bind its cwd by the actual staged Cargo package.
                match=re.search(r'/build/([^/]+)/[0-9a-f]+/out/',str(depfile))
                if match is None:raise RuntimeError('unresolved relative dep-info input: '+name+' in '+str(depfile))
                package=match[1];candidates=[]
                for manifest in (tree/'build').rglob('Cargo.toml'):
                    if tomllib.loads(manifest.read_text()).get('package',{}).get('name')==package and (manifest.parent/name).is_file():
                        candidates.append(manifest.parent/name)
                if len(candidates)!=1:raise RuntimeError('ambiguous relative dep-info cwd: '+name+' '+str(candidates))
                p=candidates[0]
        p=p.resolve()
        if not p.is_file(): raise RuntimeError('dep-info input missing: '+str(p))
        data=p.read_bytes()
        try: rel=p.relative_to(tree).as_posix()
        except ValueError: raise RuntimeError('input outside bound source/build tree: '+str(p))
        declared=generated_spec.get('files',{}).get(rel)
        generated=rel.startswith('build/') or declared is not None
        if declared is not None:
            if hashlib.sha256(data).hexdigest()!=declared['sha256']:
                raise RuntimeError('build-owned Rust output differs from its prepared literal: '+rel)
            script=(reference if reference is not None else tree)/declared['producer']
            if hashlib.sha256(script.read_bytes()).hexdigest()!=declared['producer_sha256']:
                raise RuntimeError('generated Rust producer changed: '+rel)
        if reference is not None and not generated:
            original=reference/rel
            if not original.is_file() or original.read_bytes()!=data:
                raise RuntimeError('compiled Rust input changed after source sealing: '+rel)
        rows[rel]={'bytes':len(data),'lines':data.count(b'\n'),'sha256':hashlib.sha256(data).hexdigest(),
                   'generated':generated,'producer':declared['producer'] if declared else None}
    result={'depfiles':depfiles,'files':rows,'unique_files':len(rows),
            'bytes':sum(r['bytes'] for r in rows.values()),'lines':sum(r['lines'] for r in rows.values()),
            'meaning':'unique dep-info source inputs; not repeated read syscalls or I/O bytes'}
    output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return result
