#!/usr/bin/env python3
"""Exercise the signed candidate repository in a fresh Debian container.

Run after stage-final-repository.py and publish-tree.sh have assembled the local
tree. This does not upload it, mount the workstation's package database, or
install on the host. Kernel and browser runtime qualification remain separate.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build
from image_platform import require_amd64_image

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
kit = (cfg.TREE / 'sparky-os')
sys.path.insert(0, str(kit))
from lean.package import stanzas

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', type=Path)
args = parser.parse_args()
repo = args.repository.resolve()
assert (repo / 'dists/mashtabba/InRelease').is_file()
assert shutil.disk_usage(base).free >= 20 * 1024**3, 'Need room for installed proof'
image_proof = json.loads((base / 'final-installed-amd64-image/status.json').read_text())
assert image_proof['passed']
image = require_amd64_image(image_proof['image'])
assert image == image_proof['image_id']
out = base / ('final-installed-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
out.mkdir()
archives = []
for path in sorted(repo.glob('pool/**/*.deb')):
    control = next(stanzas(subprocess.check_output(['dpkg-deb', '-f', str(path)], text=True)))
    assert control.get('sparky-lean-code', '').startswith('lc1 '), path
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    archives.append(dict(package=control['package'], version=control['version'],
                         architecture=control['architecture'], sha256=digest,
                         path='/repo/' + str(path.relative_to(repo))))
(out / 'archives.json').write_text(json.dumps(archives, indent=2) + '\n')
apt = [r for r in archives if r['package'] == 'sparky-stereo-apt']
assert len(apt) == 1
subprocess.run(['dpkg-deb', '-x', str(repo / Path(apt[0]['path']).relative_to('/repo')),
                str(out / 'apt-payload')], check=True)
roles = sorted({r['package'] for r in archives
                if r['package'].startswith('task-sparky-') or r['package'] == 'sparky-stereo'})
(out / 'roles.json').write_text(json.dumps(roles) + '\n')
inputs = dict(image=image, image_reference=image_proof['image'], platform='linux/amd64', repository=str(repo),
              inrelease_sha256=hashlib.sha256((repo / 'dists/mashtabba/InRelease').read_bytes()).hexdigest(),
              scope='Fresh signed-APT install, resolver and installed payload proof; not desktop/physical-output testing')
(out / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')

inner = r'''from pathlib import Path
import hashlib,json,os,subprocess,tarfile
out=Path('/proof');records=json.loads((out/'archives.json').read_text());results=[]
native=subprocess.check_output(['dpkg','--print-architecture'],text=True).strip()
foreign=subprocess.check_output(['dpkg','--print-foreign-architectures'],text=True).split()
assert native=='amd64' and foreign==['i386'],(native,foreign)
(out/'platform.json').write_text(json.dumps(dict(native=native,foreign=foreign))+'\n')
def run(name,command,timeout=1800):
 with (out/(name+'.log')).open('w') as log:
  try:rc=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=timeout).returncode
  except subprocess.TimeoutExpired:rc=124
 text=(out/(name+'.log')).read_text()
 passed=rc==0
 if '-s' in command:passed=passed and not any(l.startswith('Remv ') for l in text.splitlines())
 results.append(dict(name=name,exit_code=rc,passed=passed))
 (out/'checks.json').write_text(json.dumps(results,indent=2)+'\n')
 print(name,'PASS' if passed else 'FAIL',flush=True)
 assert passed,name
for role in json.loads((out/'roles.json').read_text()):
 run('resolve-'+role,['apt-get','-s','install',role],600)
packages=['dpkg-stereo','sparky-stereo-skills','sparky-stereo-tasks','sparky-stereo-apt',
 'wine64','wine32:i386','libwine:amd64','libwine:i386',
 'libgl1-mesa-dri:amd64','libgl1-mesa-dri:i386',
 'mesa-vulkan-drivers:amd64','mesa-vulkan-drivers:i386']
run('resolve-installed-set',['apt-get','-s','--no-install-recommends','install',*packages],600)
run('install',['apt-get','-y','--no-install-recommends','-o','Dpkg::Use-Pty=0','install',*packages],3600)
run('dpkg-audit',['dpkg','--audit'])
assert not (out/'dpkg-audit.log').read_text().strip(),'dpkg audit reported incomplete packages'
run('apt-check',['apt-get','check'])
installed=subprocess.check_output(['dpkg-query','-W','-f=${Package}\t${Version}\t${Architecture}\t${db:Status-Status}\n'],text=True)
(out/'installed.tsv').write_text(installed)
identities={tuple(line.split('\t')[:3]) for line in installed.splitlines() if line.endswith('\tinstalled')}
verified=[]
for row in records:
 if (row['package'],row['version'],row['architecture']) not in identities:continue
 path=Path(row['path'])
 with path.open('rb') as stream:assert hashlib.file_digest(stream,'sha256').hexdigest()==row['sha256']
 proc=subprocess.Popen(['dpkg-deb','--fsys-tarfile',str(path)],stdout=subprocess.PIPE)
 count=0
 with tarfile.open(fileobj=proc.stdout,mode='r|') as tar:
  for item in tar:
   target=Path('/')/item.name.removeprefix('./')
   if item.isfile():
    assert target.is_file() and not target.is_symlink(),str(target)
    with target.open('rb') as stream:got=hashlib.file_digest(stream,'sha256').digest()
    assert got==hashlib.file_digest(tar.extractfile(item),'sha256').digest(),str(target)
    assert target.stat().st_mode&0o7777==item.mode&0o7777,str(target)
    count+=1
   elif item.issym():assert target.is_symlink() and str(target.readlink())==item.linkname,str(target)
   elif item.islnk():assert os.path.samefile(target,Path('/')/item.linkname.removeprefix('./')),str(target)
 assert proc.wait()==0
 verified.append(dict(package=row['package'],version=row['version'],architecture=row['architecture'],files=count))
(out/'installed-payloads.json').write_text(json.dumps(verified,indent=2)+'\n')
for name in packages:
 package,_,arch=name.partition(':')
 assert any(r['package']==package and (not arch or r['architecture']==arch) for r in verified),name
run('lean-verify',['dpkg-stereo','--verify'])
run('tasks',['tasksel','--list-tasks'])
tasks=(out/'tasks.log').read_text()
assert 'sparky-stereo-os-developer' in tasks and 'sparky-stereo-developer' in tasks
run('diversions',['dpkg-divert','--list'])
assert '/usr/share/tasksel/descs/' in (out/'diversions.log').read_text()
run('candidate-policy',['apt-cache','policy','wine64','libwine:i386','libgl1-mesa-dri:i386','sparky-stereo-skills'])
# Fetch a retained source through the signed index without unpacking or executing it.
source=out/'source-download';source.mkdir();os.chdir(source)
run('source-download',['apt-get','source','--download-only','dpkg-stereo'])
assert list(source.glob('*.dsc'))
'''
(out / 'inner.py').write_text(inner)
recipe = '''set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[ "$(dpkg --print-architecture)" = amd64 ]
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d
apt-get update
apt-get -y --no-install-recommends install ca-certificates python3 gpgv
dpkg --add-architecture i386
rm -f /etc/apt/sources.list.d/debian.sources
printf 'deb https://deb.debian.org/debian testing main contrib non-free non-free-firmware\n' > /etc/apt/sources.list
printf 'deb [signed-by=/repo/sparky-stereo-repo.asc] file:/repo mashtabba main\ndeb-src [signed-by=/repo/sparky-stereo-repo.asc] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/candidate.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
cp /host-sparky.sources /etc/apt/sources.list.d/sparky.sources
cp /bootstrap-sparky.asc /etc/apt/trusted.gpg.d/sparky-repo.asc
cp /bootstrap-multimedia.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp
cp /proof/apt-payload/etc/apt/preferences.d/* /etc/apt/preferences.d/
apt-get update
python3 /proof/inner.py
'''
(out / 'run.sh').write_text(recipe)
name = 'sparky-lc-final-installed'
command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--name', name, '--cpus', '2', '--memory', '8g',
           '-v', str(out) + ':/proof', '-v', str(repo) + ':/repo:ro',
           '-v', '/etc/apt/sources.list.d/sparky.sources:/host-sparky.sources:ro',
           '-v', '/etc/apt/trusted.gpg.d/sparky-repo.asc:/bootstrap-sparky.asc:ro',
           '-v', '/usr/share/keyrings/deb-multimedia-keyring.pgp:/bootstrap-multimedia.pgp:ro',
           image, 'bash', '/proof/run.sh']
with (out / 'driver.log').open('w') as log:
    process = start_build(command, name, log)
    while process.poll() is None:
        if shutil.disk_usage(base).free < 12 * 1024**3:
            subprocess.run(['docker', 'stop', '-t', '10', name], check=False)
            break
        time.sleep(5)
    rc = process.wait()
(out / 'status.json').write_text(json.dumps(dict(state='passed' if rc == 0 else 'needs-repair',
    exit_code=rc, scope=inputs['scope']), indent=2) + '\n')
print(out, 'PASS' if rc == 0 else 'FAIL', flush=True)
raise SystemExit(rc)
