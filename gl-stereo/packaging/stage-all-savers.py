#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stage the two all-saver upload sets and evidence only after all gates pass."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

build=Path(sys.argv[1]);stage=Path(sys.argv[2]);audit=build/'all-savers'
statuses={build/'logs': ['all-savers-core-final-build','all-savers-xscreensaver-final-build',
    'all-savers-core-final-lintian','all-savers-xscreensaver-lintian',
    'all-savers-package-audit','all-savers-installed-integrity'],
    audit:['installed-inventory-check','installed-final-functional','installed-sizing3',
           'installed-final-plasma','installed-sweep','installed-mono','installed-late',
           'installed-controlled-mono','installed-fliptext-final2','installed-collect',
           'installed-flurry','installed-flurry-check','installed-debug-equivalence',
           'installed-qualification','installed-qualification-mutations']}
for directory,names in statuses.items():
    for name in names:assert (directory/(name+'.status')).read_text().strip()=='0',name

def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

files=set();sources=build/'sources'
for version in ('gl-stereo_0.3.0-1','xscreensaver_6.09+dfsg1-2+stereo3d2'):
    changes=sources/(version+'_amd64.changes');files.add(changes)
    hashes=False;source_present=False
    for line in changes.read_text().splitlines():
        if not line.startswith(' '):hashes=line=='Checksums-Sha256:'
        elif hashes:
            sha,size,name=line.split();assert Path(name).name==name
            path=sources/name
            assert path.stat().st_size==int(size) and digest(path)==sha,name
            files.add(path);source_present |= path.suffix=='.dsc'
    assert source_present,(version,'binary-only changes')
assert len([path for path in files if path.suffix=='.dsc'])==2
installed={Path(name).name:sha for sha,name in (line.split() for line in (audit/'final-installed-debs.sha256').read_text().splitlines())}
for path in files:
    if path.suffix=='.deb':assert installed[path.name]==digest(path),('deb changed after installation',path.name)
stage.mkdir(parents=True,exist_ok=True)
assert not any(path for path in stage.iterdir() if not path.name.startswith('.')),'refuse to mix an earlier staging set'
for path in sorted(files):shutil.copy2(path,stage/path.name)
evidence=stage/'evidence';evidence.mkdir()
for directory,names in statuses.items():
    for name in names:
        for suffix in ('.status','.log'):
            path=directory/(name+suffix)
            if path.exists():shutil.copy2(path,evidence/path.name)
for path in (build/'logs'/'all-savers-build-versions.txt',audit/'final-installed-packages.txt',
             audit/'final-installed-debs.sha256',
             audit/'install-final-debs.log',audit/'plasma-final'/'final-installed-packages.txt',
             audit/'plasma-final'/'install-final-debs.log'):
    prefix='plasma-' if path.parent.name=='plasma-final' else ''
    shutil.copy2(path,evidence/(prefix+path.name))
for path in audit.glob('installed-*.json'):shutil.copy2(path,evidence/path.name)
for path in audit.glob('installed-*/results.json'):
    shutil.copy2(path,evidence/(path.parent.name+'-results.json'))
selected=json.loads((audit/'installed-selected-cases.json').read_text())
for name,directory in selected.items():
    dest=evidence/'captures'/name;dest.mkdir(parents=True)
    for filename in ('LEFT.png','RIGHT.png','kwin.png','execution.json','declaration.txt','result.json'):
        shutil.copy2(audit/directory/filename,dest/filename)
for case in (audit/'installed-reference-selected').iterdir():
    for eye in ('left','right'):
        dest=evidence/'references'/case.name/eye;dest.mkdir(parents=True)
        shutil.copy2(case/eye/'frame.png',dest/'frame.png')
controls={}
for directory in ('installed-mono','installed-mono-warmup','installed-trace-mono','installed-controlled-mono','installed-flurry-mono'):
    for item in json.loads((audit/directory/'results.json').read_text()):
        if item.get('equal') and item.get('stddev',0)>1:controls[item['id']]=audit/directory/item['id']
assert len(controls)==130
for name,case in controls.items():
    dest=evidence/'stock-2d'/name;dest.mkdir(parents=True)
    for mode in ('stock','disabled'):
        shutil.copy2(next((case/mode).glob('*.png')),dest/(mode+'.png'))
negative=evidence/'negative-controls';negative.mkdir()
shutil.copy2(audit/'installed-kwin/flurry/kwin.png',negative/'flurry-old-flat.png')
shutil.copy2(audit/'installed-kwin/flurry/execution.json',negative/'flurry-old-execution.json')
for name in ('glblur','etruscanvenus'):
    dest=evidence/'proof';dest.mkdir(exist_ok=True)
    shutil.copy2(audit/selected[name]/'kwin.png',dest/(name+'-full-sbs.png'))
(evidence/'proof'/'README.md').write_text('GLBlur: both camera histories follow their own eye through the original blur effect.\nEtruscan Venus: the mathematical surface is rendered by two cameras at gentle screen-level depth.\n')
for path in (audit/'plasma-final/installed-tests/out/plasma').glob('rig-*/*.png'):
    dest=evidence/'plasma';dest.mkdir(exist_ok=True)
    shutil.copy2(path,dest/(path.parent.name+'-'+path.name))
manifest=[]
for directory,subdirectories,names in os.walk(stage):
    subdirectories[:]=sorted(name for name in subdirectories if not name.startswith('.'))
    for name in sorted(names):
        if name.startswith('.') or name=='SHA256SUMS':continue
        path=Path(directory)/name
        manifest.append(f'{digest(path)}  {path.relative_to(stage)}\n')
(stage/'SHA256SUMS').write_text(''.join(manifest))
print('PASS:',len(files),'upload files, two complete source packages and 130 installed LEFT/RIGHT pairs staged')
