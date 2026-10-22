#!/usr/bin/env python3
"""Copy only A10's package/update/boot metadata for an isolated local simulation."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import tarfile
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

base = cfg.path('SPARKY_MIGRATION_WORK')
out = base / ('a10-state-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
out.mkdir()
remote = r'''from pathlib import Path
import hashlib,json,subprocess,sys,tarfile
paths=['etc/apt/sources.list','etc/apt/sources.list.d','etc/apt/preferences',
 'etc/apt/preferences.d','etc/apt/trusted.gpg','etc/apt/trusted.gpg.d',
 'usr/share/keyrings','var/lib/dpkg/status','var/lib/apt/extended_states',
 'var/lib/apt/lists','etc/default/grub','etc/default/grub.d']
def run(args):return subprocess.check_output(args,text=True).strip()
status=Path('/var/lib/dpkg/status').read_bytes()
metadata=dict(hostname=run(['hostname']),architectures=[run(['dpkg','--print-architecture'])]+run(['dpkg','--print-foreign-architectures']).split(),
 default_release=run(['apt-config','shell','release','APT::Default-Release']),
 status_sha256=hashlib.sha256(status).hexdigest(),kernel=run(['uname','-r']),
 apt_version=run(['dpkg-query','-W','-f=${Version}','apt']))
sys.stdout.buffer.write(b'A10_STATE_ARCHIVE_BEGIN\n');sys.stdout.buffer.flush()
def filter_member(info):
 if info.name in ['var/lib/apt/lists/lock','var/lib/apt/lists/partial','var/lib/apt/lists/auxfiles']:return None
 return info
with tarfile.open(fileobj=sys.stdout.buffer,mode='w|gz') as tar:
 for name in paths:
  path=Path('/')/name
  if path.exists():tar.add(path,arcname=name,filter=filter_member)
 raw=json.dumps(metadata).encode();info=tarfile.TarInfo('snapshot.json');info.size=len(raw)
 import io
 tar.addfile(info,io.BytesIO(raw))
assert hashlib.sha256(Path('/var/lib/dpkg/status').read_bytes()).hexdigest()==metadata['status_sha256'],'A10 package state changed during capture'
'''
command=['ssh','-oBatchMode=yes','-oConnectTimeout=8','-oIdentitiesOnly=yes',
         '-i',cfg.get('SPARKY_A10_SSH_KEY'),cfg.get('SPARKY_A10_HOST'),
         'sudo -n python3 -c '+shlex.quote(remote)]
with (out/'ssh.log').open('wb') as log:
    proc=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=log)
    while True:
        line=proc.stdout.readline()
        if line==b'A10_STATE_ARCHIVE_BEGIN\n':break
        if not line:raise RuntimeError('A10 did not start the metadata stream')
        log.write(line)
    with (out/'state.tar.gz').open('xb') as stream:
        while chunk:=proc.stdout.read(1024*1024):stream.write(chunk)
    assert proc.wait()==0,'A10 capture failed; retain logs'
root=out/'root';root.mkdir()
with tarfile.open(out/'state.tar.gz') as tar:tar.extractall(root,filter='data')
meta=json.loads((root/'snapshot.json').read_text())
assert hashlib.sha256((root/'var/lib/dpkg/status').read_bytes()).hexdigest()==meta['status_sha256']
assert meta['hostname']==cfg.get('SPARKY_A10_HOSTNAME')
(cfg.path('SPARKY_RUN_RECORD')/'a10-uplift/snapshot-location.json').write_text(
    json.dumps(dict(root=str(root),metadata=meta,scope='Copied metadata only; A10 unchanged'),indent=2)+'\n')
print('Captured A10 upgrade snapshot:',root,flush=True)
