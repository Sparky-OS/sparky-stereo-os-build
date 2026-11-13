#!/usr/bin/python3
"""Keep Debian's native regeneration, then copy the prequalified Rust input."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

root=Path(__file__).resolve().parents[2]
spec=json.loads((root/'debian/sparky-wit-projection.json').read_text())
if len(sys.argv)!=3 or sys.argv[1]!=spec['version'] or sys.argv[2] not in spec['paths']:
    raise SystemExit('unexpected WIT regeneration request; fixed experiment refuses another version/path')
original=root/spec['producer']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if sha(original)!=spec['producer_sha256']:raise SystemExit('authored WIT producer changed')
# Bash's source arguments preserve the original script's $0, and therefore its literal bytes.
subprocess.run(['bash','-c','. "$1" "$2" "$3"','debian/scripts/build-wit-bindgen.sh',
                str(original),sys.argv[1],sys.argv[2]],cwd=root,check=True,env=dict(os.environ,LC_ALL='C'))
name=spec['paths'][sys.argv[2]];row=spec['files'][name];target=root/name
if sha(target)!=row['authored_sha256']:raise SystemExit('WIT generated Rust differs from prepared authored literal')
prepared=root/row['form_asset']
if sha(prepared)!=row['sha256']:raise SystemExit('prepared WIT Rust projection changed')
target.write_bytes(prepared.read_bytes())
print('WIT: original native regeneration retained; prequalified '+spec['form']+' Rust input copied: '+name)
