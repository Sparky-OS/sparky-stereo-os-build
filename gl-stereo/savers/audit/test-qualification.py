#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Reject incomplete, stale or falsely qualified package manifests."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile

manifest=Path(sys.argv[1]);library=Path(sys.argv[2]);parent=Path(sys.argv[3])
base=Path(__file__).resolve().parent.parent
proofs=json.loads(manifest.read_text())
bootstrap=json.loads(Path('/usr/share/gl-stereo/catalogue.json').read_text())
with tempfile.TemporaryDirectory(prefix='qualification-mutations-',dir=parent) as temporary:
    root=Path(temporary);candidate=root/'manifest.json';catalogue=root/'catalogue.json'
    for mutation in ('valid','missing','duplicate','unknown','stale-layer','stale-saver','settings','false-proof','false-2d','false-composition','excess-depth','excess-residual'):
        changed=copy.deepcopy(proofs)
        if mutation=='missing':changed.pop()
        elif mutation=='duplicate':changed[-1]=changed[0]
        elif mutation=='unknown':changed[0]['id']='nonexistent-saver'
        elif mutation=='stale-layer':changed[0]['library_sha256']='0'*64
        elif mutation=='stale-saver':changed[0]['executable_sha256']='0'*64
        elif mutation=='settings':changed[0]['verification']['settings_sha256']='0'*64
        elif mutation=='false-proof':changed[0]['proof']['passed']=False
        elif mutation=='false-2d':changed[0]['verification']['stock_2d_exact']=False
        elif mutation=='false-composition':changed[0]['verification']['kwin_composition']=False
        elif mutation=='excess-depth':changed[0]['proof']['disparity_bounds_px'][1]=1000
        elif mutation=='excess-residual':changed[0]['proof']['residual_px']=2
        candidate.write_text(json.dumps(changed));catalogue.write_text(json.dumps(bootstrap))
        result=subprocess.run([sys.executable,str(base/'install-qualified.py'),str(candidate),str(catalogue),str(library)],capture_output=True,text=True)
        assert (result.returncode==0)==(mutation=='valid'),(mutation,result.stdout,result.stderr)
        if mutation=='valid':assert len(json.loads(catalogue.read_text()))==132
        print('PASS:',mutation,'accepted' if mutation=='valid' else 'rejected')
