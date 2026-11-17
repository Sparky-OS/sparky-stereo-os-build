#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare the authored and LC descriptors across clocks, zones and umasks."""
import datetime
import email.utils
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys

base, reference, work, record=map(Path,sys.argv[1:])
epoch=json.loads(record.read_text())['sourceDateEpoch']
producer=Path(__file__).resolve().parents[1]/'make-source.py'
env=dict(os.environ,SOURCE_DATE_EPOCH=str(epoch),
         SOURCE_DATE_RFC2822=email.utils.format_datetime(datetime.datetime.fromtimestamp(epoch,datetime.timezone.utc)),
         DEBFULLNAME='Daniel Ramos (Capitain Jack)',DEBEMAIL='Capitain_Jack@yahoo.com',LC_ALL='C.UTF-8',
         FAKETIME_DONT_FAKE_MONOTONIC='1')
work.mkdir(parents=True,exist_ok=True)
def hashes(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest()
            for section in ('authored','lc') for p in sorted((root/section).iterdir())
            if p.is_file() and (p.name.endswith('.dsc') or p.name.endswith('.debian.tar.xz'))
            and (section!='lc' or '+lc1.' in p.name)}
expected=hashes(reference)
assert len(expected)==4
results=[]
for name,clock,zone,mask in [('utc','2026-11-18 09:00:00','UTC',0o022),
                            ('future','2031-05-15 22:10:00','Pacific/Auckland',0o077),
                            ('local','2027-02-22 03:45:00','America/Sao_Paulo',0o002)]:
    target=work/name
    with (work/(name+'.log')).open('w') as log:
        completed=subprocess.run(['faketime',clock,'python3',str(producer),str(base),str(target)],
                                 env=dict(env,TZ=zone),umask=mask,stdout=log,stderr=subprocess.STDOUT)
    assert completed.returncode==0,(name,'producer failed')
    actual=hashes(target)
    assert actual==expected,(name,actual,expected)
    results.append({'case':name,'clock':clock,'zone':zone,'umask':oct(mask),'hashes':actual,'exit':0})
    print(name,'PASS: both source descriptors and Debian archives match',flush=True)
native=work/'dpkg-source-build'; native.mkdir()
for p in (reference/'lc').glob('*.orig.tar.*'): shutil.copy2(p,native/p.name)
dsc=next(p for p in (reference/'lc').glob('*+lc1.dsc'))
with (work/'dpkg-source-build.log').open('w') as log:
    subprocess.run(['dpkg-source','-x',str(dsc),str(native/'source')],check=True,stdout=log,stderr=subprocess.STDOUT)
    subprocess.run(['dpkg-buildpackage','-S','-us','-uc','-d'],cwd=native/'source',env=dict(env,TZ='Pacific/Auckland'),
                   umask=0o077,check=True,stdout=log,stderr=subprocess.STDOUT)
actual={key:hashlib.sha256((native/Path(key).name).read_bytes()).hexdigest() for key in expected if key.startswith('lc/')}
assert actual=={key:value for key,value in expected.items() if key.startswith('lc/')},actual
results.append({'case':'dpkg-buildpackage-S','hashes':actual,'exit':0})
print('dpkg-buildpackage -S PASS: descriptor and Debian archive match',flush=True)
(work/'results.json').write_text(json.dumps(results,indent=2)+'\n')
