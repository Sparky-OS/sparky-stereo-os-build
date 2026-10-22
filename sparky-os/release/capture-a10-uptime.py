#!/usr/bin/env python3
"""Read A10's uptime and current stereo output without changing its session."""
from datetime import datetime, timezone
import json
from pathlib import Path
import shlex
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

out = cfg.path('SPARKY_RUN_RECORD') / 'a10-uplift' / ('uptime-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
out.mkdir()
remote = r'''import datetime,json,os,pathlib,shutil,subprocess,time
def run(args,session=False):
 env=dict(os.environ)
 if session:env.update(XDG_RUNTIME_DIR='/run/user/1000',WAYLAND_DISPLAY='wayland-0',DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus')
 try:
  p=subprocess.run(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=30)
  return dict(command=args,exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr)
 except (OSError,subprocess.TimeoutExpired) as e:return dict(command=args,error=str(e))
now=datetime.datetime.now(datetime.timezone.utc)
uptime=float(pathlib.Path('/proc/uptime').read_text().split()[0])
boot=next(int(l.split()[1]) for l in pathlib.Path('/proc/stat').read_text().splitlines() if l.startswith('btime '))
commands={
 'kernel':['uname','-a'],
 'uptime':['uptime'],
 'compositor_processes':['ps','-C','kwin_wayland','-o','pid=,lstart=,etimes='],
 'versions':['dpkg-query','-W','-f=${binary:Package}\t${Version}\t${Sparky-Lean-Code}\n','linux-image-7.3.0-rc6-stereo3d8','kwin-wayland','kwin-common','kscreen','libkf6screen8','libgl1-mesa-dri','mesa-vulkan-drivers','stereo-layer','libstereo-layer0','dpkg-stereo','sparky-stereo-browser'],
 'boot_history':['sudo','-n','journalctl','--list-boots','-n','6','--no-pager'],
 'running_modules':['sh','-c','lsmod | sed -n "1p;/^amdgpu /p;/^radeon /p"'],
 'gpu_driver':['lspci','-nnk','-d','1002:']}
data=dict(captured_utc=now.isoformat(),uptime_seconds=uptime,boot_epoch=boot,boot_utc=datetime.datetime.fromtimestamp(boot,datetime.timezone.utc).isoformat(),boot_id=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip(),commands={k:run(v) for k,v in commands.items()})
for name,args in [('kscreen_outputs',['kscreen-doctor','-o']),('kscreen_json',['kscreen-doctor','-j'])]:data['commands'][name]=run(args,True)
qdbus=shutil.which('qdbus6') or shutil.which('qdbus') or '/usr/lib/qt6/bin/qdbus'
data['commands']['kwin_support']=run([qdbus,'org.kde.KWin','/KWin','org.kde.KWin.supportInformation'],True)
print('A10_UPTIME_JSON_BEGIN')
print(json.dumps(data))
'''
command = ['ssh', '-oBatchMode=yes', '-oConnectTimeout=8', '-oIdentitiesOnly=yes',
           '-i', cfg.get('SPARKY_A10_SSH_KEY'), cfg.get('SPARKY_A10_HOST'),
           'python3 -c ' + shlex.quote(remote)]
p = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180)
(out / 'ssh.log').write_text(p.stderr)
assert p.returncode == 0, 'Read-only capture failed; see ssh.log'
prefix, payload = p.stdout.split('A10_UPTIME_JSON_BEGIN\n', 1)
(out / 'ssh-banner.txt').write_text(prefix)
data = json.loads(payload)
(out / 'state.json').write_text(json.dumps(data, indent=2) + '\n')
for name, result in data['commands'].items():
    if 'stdout' in result:
        (out / (name + '.txt')).write_text(result['stdout'])
print(out)
print(json.dumps({k:data[k] for k in ['captured_utc','boot_utc','uptime_seconds']}))
for name in ['kernel','compositor_processes','versions','kscreen_outputs']:
    print(name, data['commands'][name])
