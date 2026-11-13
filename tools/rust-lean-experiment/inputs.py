#!/usr/bin/env python3
"""Census of unique Rust source inputs named by actual compiler dep-info."""
import hashlib
import json
from pathlib import Path
import re


def census(tree, output, reference=None):
    names, depfiles = set(), 0
    for p in (tree/'build').rglob('*.d'):
        depfiles += 1
        text=p.read_text(errors='strict').replace('\\\n','')
        # Rust's generated dep-info uses Make backslash quoting, including spaces.
        for line in text.splitlines():
            if not line or line.startswith('#') or ': ' not in line: continue
            rhs=line.split(': ',1)[1]
            for token in re.findall(r'(?:\\.|[^\s])+',rhs):
                token=re.sub(r'\\(.)',r'\1',token)
                if token.endswith('.rs'): names.add(token)
    if not depfiles or not names: raise RuntimeError('build produced no Rust dep-info inputs')
    rows={}
    for name in sorted(names):
        p=Path(name)
        if not p.is_absolute(): p=tree/p
        p=p.resolve()
        if not p.is_file(): raise RuntimeError('dep-info input missing: '+str(p))
        data=p.read_bytes()
        try: rel=p.relative_to(tree).as_posix()
        except ValueError: raise RuntimeError('input outside bound source/build tree: '+str(p))
        if reference is not None and not rel.startswith('build/'):
            original=reference/rel
            if not original.is_file() or original.read_bytes()!=data:
                raise RuntimeError('compiled Rust input changed after source sealing: '+rel)
        rows[rel]={'bytes':len(data),'lines':data.count(b'\n'),'sha256':hashlib.sha256(data).hexdigest(),
                   'generated':rel.startswith('build/')}
    result={'depfiles':depfiles,'files':rows,'unique_files':len(rows),
            'bytes':sum(r['bytes'] for r in rows.values()),'lines':sum(r['lines'] for r in rows.values()),
            'meaning':'unique dep-info source inputs; not repeated read syscalls or I/O bytes'}
    output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return result
