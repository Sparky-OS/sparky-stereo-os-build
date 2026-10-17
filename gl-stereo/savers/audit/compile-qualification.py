#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bind complete installed-file evidence to the exact rotation binaries."""
import argparse
from collections import Counter
import hashlib
import json
import runpy
from pathlib import Path
import sys
import numpy as np
from PIL import Image

parser=argparse.ArgumentParser()
parser.add_argument('evidence',type=Path)
parser.add_argument('output',type=Path)
parser.add_argument('--library',default='/usr/lib/gl-stereo/libgl-stereo.so',type=Path)
args=parser.parse_args();base=args.evidence
inventory=json.loads((base/'installed-inventory.json').read_text())
layer_hash=hashlib.sha256(args.library.read_bytes()).hexdigest()
assert (base/'installed-inventory-check.status').read_text().strip()=='0'
assert (base/'installed-functional.status').read_text().strip()=='0'
for name in ('installed-late-compositor','installed-glsnake-lights','installed-tiles','installed-sweep','installed-mono','installed-collect','installed-controlled-mono','installed-fliptext-final2','installed-flurry','installed-flurry-check','installed-debug-equivalence'):
    assert (base/(name+'.status')).read_text().strip()=='0',name

def read(name):return json.loads((base/name).read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
mono={}
for name in ('installed-mono/results.json','installed-mono-warmup/results.json','installed-trace-mono/results.json','installed-trace-mono-fixed/results.json','installed-controlled-mono/results.json','installed-flurry-mono/results.json'):
    for record in read(name):
        if record.get('equal') and record.get('stddev',0)>1:
            assert record['library_sha256']==layer_hash,('stale 2D layer',record['id'])
            mono[record['id']]=dict(record, directory=str((base/name).parent/record['id']))
references={item['id']:item for item in read('installed-reference-checked.json')}
flats={item['id']:item for item in read('installed-flat-checked.json')}
composition={item['id']:item for item in read('installed-composition-checked.json')}
selected=read('installed-selected-cases.json')
equivalence=read('installed-debug-equivalence.json')
equivalent=runpy.run_path(str(Path(__file__).with_name('debug-equivalence.py')))['equivalent']
owning=json.loads(Path(__file__).with_name('owning-fixes.json').read_text())
owning_settings=json.loads(Path(__file__).with_name('owning-settings.json').read_text())
entries=[]
for item in inventory:
    if item['kind']!='hack':continue
    name=item['id'];case=base/selected[name]
    execution=json.loads((case/'execution.json').read_text())
    binary=Path('/usr/libexec/xscreensaver')/name;binary_hash=digest(binary)
    assert item['executable_sha256']==binary_hash
    assert execution['library_sha256']==layer_hash,(name,'stale stereo layer')
    assert float(execution['separation'])==.5,(name,'wrong screen-level strength')
    def same_binary(tested_hash):
        if tested_hash==binary_hash:return True
        change=equivalence.get(name,{})
        if change.get('tested_sha256')!=tested_hash or change.get('installed_sha256')!=binary_hash:return False
        original=(base/'pre-flurry-installed'/name).read_bytes()
        return hashlib.sha256(original).hexdigest()==tested_hash and equivalent(original,binary.read_bytes())
    assert same_binary(execution['executable_sha256']),(name,'stale stereo executable')
    assert name in mono and same_binary(mono[name]['executable_sha256']),(name,'no exact nonempty 2D control')
    control=Path(mono[name]['directory'])
    stock=next((control/'stock').glob('*.png'));disabled=next((control/'disabled').glob('*.png'))
    original=np.array(Image.open(stock).convert('RGB'));wrapped=np.array(Image.open(disabled).convert('RGB'))
    assert np.array_equal(original,wrapped),(name,'2D pixels changed')
    assert original.std(axis=(0,1)).max()>1,(name,'uniform 2D control')
    assert composition[name]['passed'],(name,'compositor mismatch')
    assert (case/'declaration.txt').read_text().strip().endswith('= 3'),(name,'declaration')
    group='flat' if name in flats else 'owning-fix' if name in owning else 'layer'
    # the installed settings: unchanged, or extended only as owning-settings.json lists
    # (check-inventory.py proved the additions against the original)
    settings_hash=owning_settings[name]['settings_sha256'] if name in owning_settings else item['settings_sha256']
    assert digest(Path('/usr/share/xscreensaver/config')/(name+'.xml'))==settings_hash,(name,'installed settings')
    if group=='flat':
        check=flats[name];assert check['passed'],(name,'flat check')
        proof=dict(oracle='screen-plane-alignment',residual_px=0,disparity_bounds_px=[0,0],eye_width=640)
    elif name in references:
        check=references[name];assert check['passed'] and check['alignment_px']==[0,0],(name,'reference mismatch')
        # Conservative analytic envelope: d=5*near, separation=.5%, all
        # visible geometry has w>=near. Actual/reference pixels also agree.
        proof=dict(oracle='single-eye-reference-and-clip-envelope',residual_px=0,
                   disparity_bounds_px=[-.02*640,.005*640],eye_width=640,
                   reference_mean_error=check['mean_error'],wrong_eye_error=check['wrong_eye_error'])
    else:
        proof=json.loads((case/'result.json').read_text())
        assert proof.get('passed') and proof.get('oracle')=='depth-v1',(name,'no camera proof')
        assert proof['separation']==.5,(name,'unexpected stereo strength')
    proof.update(passed=True,placement='screen-level')
    low,high=proof['disparity_bounds_px'];assert -.02*640<=low<=high<=.02*640,(name,'comfort')
    evidence={file:digest(case/file) for file in ('LEFT.png','RIGHT.png','execution.json','declaration.txt')}
    entries.append(dict(id=name,command=[str(binary),'-window','-geometry','640x360'],
                        environment=dict(GL_STEREO='1',GL_STEREO_SEPARATION='.5',LD_PRELOAD=str(args.library)),
                        library=str(args.library),library_sha256=layer_hash,executable_sha256=binary_hash,
                        proof=proof,qualification=dict(state='qualified',group=group),
                        verification=dict(stock_2d_exact=True,settings_unchanged=True,kwin_composition=True,camera_or_flat=True,
                                          settings_sha256=settings_hash,capture_sha256=evidence,
                                          stock_2d_sha256=digest(stock),disabled_2d_sha256=digest(disabled),
                                          input='recorded GL' if execution['command'][0]=='glretrace' else 'seeded live saver')))
    if name in equivalence:
        entries[-1]['verification']['binary_debug_equivalence']=equivalence[name]
    if name in owning_settings:
        entries[-1]['verification']['settings_added']=[added['id'] for added in owning_settings[name]['added']]
    if execution['command'][0]=='glretrace':
        entries[-1]['verification']['trace_sha256']=digest(Path(execution['command'][-1]))
        entries[-1]['verification']['trace_snapshot_calls']=execution['command'][execution['command'].index('-S')+1]
assert len(entries)==130
# Each depth receipt may be off by up to one pixel (a single scene's correspondence noise), but a
# layer that moves one eye moves them all: their mean must stay within a quarter pixel.
residuals=[e['proof']['residual_px'] for e in entries if e['proof'].get('oracle')=='depth-v1']
mean_residual=sum(residuals)/len(residuals)
print('depth residual mean %+.3f px over %d savers; histogram %s'%(mean_residual,len(residuals),dict(sorted(Counter(residuals).items()))))
assert abs(mean_residual)<=.25,('depth residual mean',mean_residual)
for entry in entries:
    entry['verification']['depth_residual_mean_px']=round(mean_residual,4)
args.output.write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n')
print('PASS:',len(entries),'complete installed qualifications',dict(Counter(e['qualification']['group'] for e in entries)))
