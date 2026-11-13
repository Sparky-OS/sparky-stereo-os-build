#!/usr/bin/env python3
"""Retain reviewed crates' documentation in C by restoring exact qualified B inputs."""
import argparse
import hashlib
import json
import tarfile
from pathlib import Path


def retain(target, b_source, ledger_path, crate, reason, record):
    if Path(crate).is_absolute() or '..' in Path(crate).parts:
        raise ValueError('crate must be a safe source-relative path')
    ledger=json.loads(ledger_path.read_text())['files']
    changed={}
    def inputs():
        if b_source.is_dir():
            for p in (b_source/crate).rglob('*.rs'):
                if not p.is_symlink():yield p.relative_to(b_source).as_posix(),p.read_bytes()
        else:
            with tarfile.open(b_source,mode='r|gz') as tf:
                for m in tf:
                    name=m.name.removeprefix('./')
                    if m.isfile() and name.startswith(crate+'/') and name.endswith('.rs'):
                        yield name,tf.extractfile(m).read()
    for name,new in inputs():
        if name not in ledger:continue
        dst=target/name
        old=dst.read_bytes()
        row=ledger[name]
        if 'left' in row:
            if old!=new:
                raise RuntimeError('preserved source differs: '+name)
            continue
        sha=lambda data:hashlib.sha256(data).hexdigest()
        if sha(new)!=row['sha256_B'] or sha(old) not in (row['sha256_B'],row['sha256_C']):
            raise RuntimeError('source does not match the qualified B/C ledger: '+name)
        if old!=new:
            dst.write_bytes(new)
            changed[name]=(sha(old),sha(new))
    # A configured build has intentionally pruned vendor checksums; a sealed
    # source still has entries, which must follow the exact old/new chain.
    for path in (target/crate).rglob('.cargo-checksum.json'):
        obj=json.loads(path.read_text());dirty=False
        for name,digest in obj.get('files',{}).items():
            rel=(path.parent/name).relative_to(target).as_posix()
            if rel in changed:
                old,new=changed[rel]
                if digest!=old:
                    raise RuntimeError('unexpected checksum before doc retention: '+rel)
                obj['files'][name]=new;dirty=True
        if dirty:path.write_text(json.dumps(obj,sort_keys=True)+'\n')
    existing=json.loads(record.read_text()) if record.exists() else {}
    existing[crate]={'reason':reason,'changed':changed}
    record.write_text(json.dumps(existing,indent=2,sort_keys=True)+'\n')
    print(f'Retained docs for {crate}: {len(changed)} exact B source files')


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    for n in ('target','b_source','ledger','record'):ap.add_argument(n,type=Path)
    ap.add_argument('crate');ap.add_argument('reason')
    a=ap.parse_args();retain(a.target,a.b_source,a.ledger,a.crate,a.reason,a.record)
