#!/bin/bash
# Model-free installed upgrade/removal proof, entirely inside the disposable rig.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
cat /proc/loadavg > /out/load-before.txt
python3 - <<'PY'
from pathlib import Path
import json
for p in Path('/etc/apt/sources.list.d').glob('*'):p.unlink()
rows=[]
for s in json.loads(Path('/archive/sources.json').read_text()):
 rows.append('deb [target=Packages check-valid-until=no signed-by='+s['keyring']+'] '+s['uri']+' '+s['suite']+' '+' '.join(s['components']))
Path('/etc/apt/sources.list').write_text('\n'.join(rows)+'\n')
PY
apt-get -o Acquire::Languages=none -o Acquire::Check-Valid-Until=false update > /out/update.log 2>&1
baseline=(/row70/graphics-0.2.17/sparky-stereo-graphics_0.2.17_amd64.deb /row70/partners-0.1.2/sparky-stereo-partners_0.1.2+lc1_amd64.deb /vibe-stage/sparky-stereo-vibe_0.1.1+lc1_all.deb /vibe-stage/sparky-stereo-integration_0.1.5+lc1_all.deb)
apt-get -s --no-install-recommends install "${baseline[@]}" > /out/baseline-plan.txt 2>&1
apt-get --print-uris -y --no-install-recommends install "${baseline[@]}" > /out/baseline-uris.txt 2>&1
if [ "${PLAN_ONLY:-0}" = 1 ]; then exit 0; fi
! grep -q '^Remv ' /out/baseline-plan.txt
apt-get -y --no-install-recommends install "${baseline[@]}" > /out/baseline-install.log 2>&1
if [ "${BASELINE_ONLY:-0}" = 1 ]; then exit 0; fi
previous=(/previous/libcaptiond-client0_*.deb /previous/captiond_*.deb /previous/kaption-common_*.deb /previous/kaption_*.deb /previous/sparky-stereo-partners_*.deb /previous/sparky-stereo-live-captions_*.deb)
apt-get -y --no-install-recommends install "${previous[@]}" > /out/predecessor-install.log 2>&1
python3 - <<'INNER'
import subprocess,json
from pathlib import Path
expected=[];versions={}
for name in ('libcaptiond-client0','captiond','kaption-common','kaption','sparky-stereo-partners','sparky-stereo-live-captions'):
 p,=Path('/stage').glob(name+'_*.deb')
 wanted=subprocess.check_output(['dpkg-deb','-f',str(p),'Version'],text=True).strip()
 current=subprocess.check_output(['dpkg-query','-W','-f=${Version}',name],text=True).strip()
 versions[name]={'before':current,'after':wanted}
 if wanted!=current:expected.append(name)
Path('/out/expected-upgrade.json').write_text(json.dumps(expected))
Path('/out/upgrade-versions.json').write_text(json.dumps(versions,indent=2)+'\n')
INNER
# Synthetic text witnesses, never Whisper data and never opened by a recognizer.
python3 - <<'PY'
from pathlib import Path
import hashlib,json
home=Path('/home/builder');rows=[]
for rel in ('.config/kaptionrc','.config/captiond/captiond.conf','.config/sparky-stereo-partnersrc','.local/share/captiond/models/personal-file.bin','.local/share/github.com.thewh1teagle.vibe/app_config.json'):
 p=home/rel;p.parent.mkdir(parents=True,exist_ok=True)
 assert not p.exists(),p
 p.write_text('lc73 personal preservation witness; no speech model\n')
 rows.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
Path('/out/personal-before.json').write_text(json.dumps(rows,indent=2)+'\n')
PY
upgrade=(/stage/libcaptiond-client0_*.deb /stage/captiond_*.deb /stage/kaption-common_*.deb /stage/kaption_*.deb /stage/sparky-stereo-partners_*.deb /stage/sparky-stereo-live-captions_*.deb)
apt-get -s --no-install-recommends install "${upgrade[@]}" > /out/upgrade-plan.txt 2>&1
apt-get --print-uris -y --no-install-recommends install "${upgrade[@]}" > /out/upgrade-uris.txt 2>&1
! grep -q '^Remv ' /out/upgrade-plan.txt
python3 - <<'INNER'
from pathlib import Path
import json
expected=set(json.loads(Path('/out/expected-upgrade.json').read_text()))
found={line.split()[1] for line in Path('/out/upgrade-plan.txt').read_text().splitlines() if line.startswith('Inst ')}
assert expected==found,(expected,found)
INNER
apt-get -y --no-install-recommends install "${upgrade[@]}" > /out/upgrade-install.log 2>&1
python3 - <<'INNER'
import json,subprocess
from pathlib import Path
versions=json.loads(Path('/out/upgrade-versions.json').read_text())
for name,value in versions.items():
    found=subprocess.check_output(['dpkg-query','-W','-f=${Version}',name],text=True).strip()
    assert found==value['after'],(name,value,found)
Path('/out/installed-versions.json').write_text(json.dumps(versions,indent=2)+'\n')
INNER
systemctl --global is-enabled sparky-stereo-live-captions.service > /out/activation.txt || test "$?" = 1
grep -x disabled /out/activation.txt
! pgrep -x captiond
! pgrep -x kaption
find /etc/systemd/user /home/builder -type l -name '*live-captions*' -print > /out/activation-links.txt
test ! -s /out/activation-links.txt
dpkg-query -L sparky-stereo-partners sparky-stereo-live-captions > /out/package-files.txt
apt-get -s remove sparky-stereo-live-captions sparky-stereo-partners > /out/remove-plan.txt 2>&1
python3 - <<'PY'
from pathlib import Path
lines=Path('/out/remove-plan.txt').read_text().splitlines()
assert {l.split()[1] for l in lines if l.startswith('Remv ')}=={'sparky-stereo-live-captions','sparky-stereo-partners'}
assert not [l for l in lines if l.startswith('Inst ')]
PY
apt-get -y remove sparky-stereo-live-captions sparky-stereo-partners > /out/remove.log 2>&1
python3 - <<'PY'
from pathlib import Path
import hashlib,json
rows=json.loads(Path('/out/personal-before.json').read_text())
for row in rows:
 p=Path(row['path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],p
Path('/out/personal-after.json').write_text(json.dumps(rows,indent=2)+'\n')
print('PASS upgrade Inst, removal Remv, installation off, five personal files preserved')
PY
cat /proc/loadavg > /out/load-after.txt
