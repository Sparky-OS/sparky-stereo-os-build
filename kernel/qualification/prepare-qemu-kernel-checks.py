#!/usr/bin/env python3
"""Qualify installed candidate QEMU, then retain it as the kernel VM test image."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg
from build_slots import start_build

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
tools = base / 'kernel-validation-tools'
original = json.loads((tools / 'status.json').read_text())
assert original['passed']
out = base / 'qemu-installed-check'
out.mkdir(exist_ok=False)
job = base / 'jobs/qemu-amd64'
status = json.loads((job / 'status.json').read_text())
assert status['state'] == 'candidate-needs-review'
packages = []
for name in ['qemu-system-x86', 'qemu-system-common', 'qemu-system-data', 'qemu-utils']:
    paths = list(job.glob(name + '_*+lc1_*.deb'))
    assert len(paths) == 1
    packages.append(paths[0])
(out / 'input-packages.json').write_text(json.dumps([
    dict(path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in packages], indent=2) + '\n')
check = '''import hashlib,json,subprocess,tarfile
from pathlib import Path
payloads=[]
for record in json.loads(Path('/evidence/input-packages.json').read_text()):
 archive=Path('/packages')/Path(record['path']).name
 assert hashlib.sha256(archive.read_bytes()).hexdigest()==record['sha256']
 proc=subprocess.Popen(['dpkg-deb','--fsys-tarfile',str(archive)],stdout=subprocess.PIPE)
 count=0
 with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:
  for member in tar:
   target=Path('/')/member.name.removeprefix('./')
   if member.isfile():
    assert target.is_file() and not target.is_symlink(),str(target)
    assert hashlib.sha256(target.read_bytes()).digest()==hashlib.sha256(tar.extractfile(member).read()).digest(),str(target)
    assert target.stat().st_mode&0o7777==member.mode&0o7777,str(target)
    count+=1
   elif member.issym():assert target.is_symlink() and str(target.readlink())==member.linkname,str(target)
 assert proc.wait()==0
 payloads.append(dict(archive=archive.name,sha256=record['sha256'],files=count))
Path('/evidence/payload-check.json').write_text(json.dumps(dict(passed=True,packages=payloads),indent=2)+'\\n')
version=subprocess.check_output(['qemu-system-x86_64','--version'],text=True)
assert '11.1.2' in version
commands=[{'execute':'qmp_capabilities'},
          {'execute':'qom-get','arguments':{'path':'/machine/peripheral/stereo0','property':'stereo'}},
          {'execute':'query-status'}, {'execute':'quit'}]
process=subprocess.run(['qemu-system-x86_64','-machine','q35,accel=kvm','-m','128',
    '-nodefaults','-device','virtio-gpu-pci,id=stereo0,stereo=on','-display','none',
    '-S','-qmp','stdio'],input='\\n'.join(json.dumps(c) for c in commands)+'\\n',
    text=True,capture_output=True,timeout=30)
Path('/evidence/qmp.log').write_text(process.stdout+'\\nSTDERR:\\n'+process.stderr)
responses=[json.loads(l) for l in process.stdout.splitlines() if l.startswith('{')]
assert process.returncode==0,process.stderr
assert not any('error' in r for r in responses),responses
assert any(r.get('return') is True for r in responses),responses
assert any(isinstance(r.get('return'),dict) and r['return'].get('running') is False for r in responses)
Path('/evidence/runtime.json').write_text(json.dumps({'passed':True,'version':version,
    'scope':'installed KVM/QMP and stereo device property; no paired-display proof'},indent=2)+'\\n')
'''
(out / 'check.py').write_text(check)
recipe = '''set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
dpkg-query -W -f='${Package} ${Version}\n' 'qemu-system-*' > /evidence/prior-qemu-versions.txt
apt-get -y --allow-downgrades --no-install-recommends install /packages/qemu-system-x86_*+lc1_amd64.deb /packages/qemu-system-common_*+lc1_amd64.deb /packages/qemu-system-data_*+lc1_all.deb /packages/qemu-utils_*+lc1_amd64.deb
python3 /evidence/check.py
/bench/bench --work /evidence/doctor doctor
rm -rf /var/lib/apt/lists/*
'''
name = 'sparky-lc-qemu-installed-check'
command = ['docker','run','--name',name,'--cpus','4','--device','/dev/kvm',
    '-v',str(job)+':/packages:ro','-v',str(out)+':/evidence',
    '-v',str(cfg.TREE / 'kernel/qualification/hibernate-bench') + ':/bench:ro',
    original['image'],'bash','-c',recipe]
with (out / 'check.log').open('w') as log:
    process = start_build(command,name,log)
    rc = process.wait()
if rc:
    (out / 'status.json').write_text(json.dumps(dict(passed=False,exit_code=rc))+'\n')
    raise SystemExit(rc)
tag = 'sparky-lc-kernel-checks-qemu:20261020'
image = subprocess.check_output(['docker','commit',name,tag],text=True).strip()
subprocess.run(['docker','rm',name],check=True)
record = dict(passed=True,image=tag,image_id=image,base_image=original,
              scope='validation tools with candidate QEMU; kernel tests still pending')
(out / 'status.json').write_text(json.dumps(record,indent=2)+'\n')
shutil.copy2(tools/'status.json',tools/'baseline-status.json')
(tools/'status.json').write_text(json.dumps(record,indent=2)+'\n')
print('Candidate QEMU installed check passed; kernel validation image retained',flush=True)
