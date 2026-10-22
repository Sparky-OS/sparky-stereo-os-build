#!/usr/bin/env python3
"""Wait for the browser candidate, install it in isolation and replay M5 cases.

No host session, display connector, user profile or package database is mounted.
The render node is used only by a private headless compositor. The result still
requires capture inspection and is not physical-output qualification.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import time
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build
from browser_fixtures import copy_media

base = cfg.path('SPARKY_MIGRATION_WORK')
work = base / 'jobs/sparky-stereo-browser-amd64'
while True:
    status_path = work / 'status.json'
    if status_path.exists():
        status = json.loads(status_path.read_text())
        if status['state'] == 'candidate-needs-review':
            break
        if status['state'] == 'needs-repair':
            raise SystemExit('Browser needs repair; runtime checks remain unstarted')
    time.sleep(10)
archives = list(work.glob('sparky-stereo-browser_*_amd64.deb'))
assert len(archives) == 1
archive = archives[0]
out = base / 'browser-installed-check'
out.mkdir()
image = 'sparky-lc-browser-checks:20261020'
parent = 'waterfox-stereo-pkgbench:m5'
parent_id = subprocess.check_output(['docker', 'image', 'inspect', parent, '--format', '{{.Id}}'], text=True).strip()
inputs = dict(archive=str(archive), sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
              parent_image=parent, parent_image_id=parent_id,
              scope='Installed candidate in private headless Stereo KWin; no physical-output qualification')
(out / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
verify = '''from pathlib import Path
import hashlib,json,subprocess,tarfile
proc=subprocess.Popen(['dpkg-deb','--fsys-tarfile','/candidate.deb'],stdout=subprocess.PIPE)
checked=0
with tarfile.open(fileobj=proc.stdout,mode='r|') as archive:
 for member in archive:
  path=Path('/')/member.name.removeprefix('./')
  if member.isfile():
   assert path.is_file() and not path.is_symlink(),str(path)
   assert hashlib.sha256(path.read_bytes()).digest()==hashlib.sha256(archive.extractfile(member).read()).digest(),str(path)
   checked+=1
  elif member.issym():assert path.is_symlink() and str(path.readlink())==member.linkname,str(path)
assert proc.wait()==0
Path('/proof/payload-check.json').write_text(json.dumps(dict(passed=True,files=checked))+'\\n')
'''
(out / 'verify-payload.py').write_text(verify)
name = 'sparky-lc-browser-install'
command = ['docker', 'run', '--name', name, '--user', '0', '--cpus', '2', '--memory', '4g',
           '-v', str(archive) + ':/candidate.deb:ro', '-v', str(out) + ':/proof',
           parent, 'bash', '-c', 'set -e; export DEBIAN_FRONTEND=noninteractive; dpkg -i /candidate.deb; python3 /proof/verify-payload.py']
with (out / 'install.log').open('w') as log:
    process = start_build(command, name, log)
    rc = process.wait()
if rc:
    (out / 'status.json').write_text(json.dumps(dict(state='needs-repair',stage='installation',exit_code=rc))+'\n')
    raise SystemExit(rc)
subprocess.run(['docker', 'commit', name, image], check=True, stdout=subprocess.DEVNULL)
subprocess.run(['docker', 'rm', name], check=True, stdout=subprocess.DEVNULL)
inputs['image_id'] = subprocess.check_output(['docker', 'image', 'inspect', image, '--format', '{{.Id}}'], text=True).strip()
tests = base / 'browser-source/recipe/tests'
baseline_path = (cfg.path('SPARKY_BROWSER_WORK') / 'runs-m5/after3/stereo3d5.json')
baseline = json.loads(baseline_path.read_text())
assert len(baseline['cases']) == 77 and all(r.get('pass') for r in baseline['cases'].values())
inputs['baseline_report_sha256'] = hashlib.sha256(baseline_path.read_bytes()).hexdigest()
inputs['test_sources'] = {str(p.relative_to(tests)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in tests.rglob('*') if p.is_file() and not p.is_symlink()}
(out / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
home = out / 'home'
home.mkdir()
uid, gid = os.getuid(), os.getgid()
if not uid:
    raise SystemExit('Run this driver as the workstation user, not root')
(out / 'passwd').write_text(f'root:x:0:0:root:/root:/bin/bash\nbuilder:x:{uid}:{gid}:builder:/proof/home:/bin/bash\n')
(out / 'group').write_text(f'root:x:0:\nbuilder:x:{gid}:\n')
render = Path('/dev/dri/renderD128')
assert render.exists()
vendor = Path('/sys/class/drm/renderD128/device/vendor').read_text().strip()
assert vendor == '0x1002', ('The accepted bench uses the AMD render node', vendor)
inputs['render_node'] = str(render)
inputs['render_vendor'] = vendor
(out / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
results = []
media = copy_media(out)
for case in baseline['cases']:
    rig = subprocess.check_output(['python3', str(tests / 'case-rig.py'), case], text=True).strip()
    command = ['docker', 'run', '--rm', '--name', 'sparky-lc-browser-runtime', '--user', f'{uid}:{gid}',
               '--cpus', '2', '--memory', '12g', '--shm-size', '2g', '--device', str(render),
               '--group-add', str(render.stat().st_gid), '-e', 'HOME=/proof/home', '-e', 'TZ=UTC',
               '-e', 'KWIN_LOG_DIR=/proof', '-v', str(out) + ':/proof', '-v', str(tests) + ':/bench:ro',
               '-v', str(media) + ':/media',
               '-v', str(out / 'passwd') + ':/etc/passwd:ro', '-v', str(out / 'group') + ':/etc/group:ro']
    if rig:
        command += ['-e', 'KWIN_OUTPUT_CONFIG=/bench/rig/kwinoutputconfig-' + rig + '.json']
        args = tests / 'rig' / ('kwinoutputconfig-' + rig + '.args')
        if args.exists():
            command += ['-e', 'KWIN_ARGS=' + args.read_text().strip()]
    command += [image, 'bash', '/bench/stereo-in-container.sh', '/bench/stereo-probe.py',
                '/usr/lib/sparky-stereo-browser/sparky-stereo-browser', '/media', '/proof/results',
                'lean-m5', case]
    with (out / (case + '.log')).open('w') as log:
        process = start_build(command, 'sparky-lc-browser-runtime', log)
        try:
            rc = process.wait(timeout=180)
        except subprocess.TimeoutExpired:
            subprocess.run(['docker', 'stop', '-t', '5', 'sparky-lc-browser-runtime'], check=False)
            process.wait()
            rc = 124
    result_path = out / 'results/lean-m5.json'
    result = json.loads(result_path.read_text())['cases'].get(case, {}) if result_path.exists() else {}
    passed = rc == 0 and result.get('pass') is True
    results.append(dict(case=case,passed=passed,exit_code=rc))
    (out / 'results-summary.json').write_text(json.dumps(results,indent=2)+'\n')
    print(case, 'PASS' if passed else 'FAIL', flush=True)
    if not passed:
        break
passed = len(results) == len(baseline['cases']) and all(r['passed'] for r in results)
(out / 'status.json').write_text(json.dumps(dict(
    state='automated-passed-needs-capture-review' if passed else 'needs-repair',
    cases=len(results),expected=len(baseline['cases']),passed=passed,
    scope=inputs['scope']),indent=2)+'\n')
raise SystemExit(not passed)
