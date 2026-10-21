#!/usr/bin/env python3
"""Regression: a base theme must not also package the optional menubar files."""
from pathlib import Path
import hashlib,io,json,subprocess,tarfile
import argparse
p=argparse.ArgumentParser(description="Check Kubabbar package ownership with real dpkg unpack transitions in empty test roots. Run in a disposable root-capable environment.")
for option in ['old-base','old-menu','conflicting-base','new-base','new-menu','output']:
 p.add_argument('--'+option,type=Path,required=True)
args=p.parse_args()
out=args.output.resolve();assert not out.exists(), 'Use a new output directory'
out.mkdir(parents=True)
base='sparky-stereo-look-kubabbar-glass';menu=base+'-menubar'
oldbase=args.old_base.resolve();oldmenu=args.old_menu.resolve();badbase=args.conflicting_base.resolve()
newbase=args.new_base.resolve();newmenu=args.new_menu.resolve()
def payload(deb):
 with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(deb)]))) as tar:
  return {m.name.removeprefix('./'):hashlib.sha256(tar.extractfile(m).read()).hexdigest() for m in tar if m.isfile()}
for deb in [oldbase,oldmenu,badbase,newbase,newmenu]:
 with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['dpkg-deb','--ctrl-tarfile',str(deb)]))) as tar:
  assert not {m.name.removeprefix('./') for m in tar}&{'preinst','postinst','prerm','postrm','triggers'},'Use a full container if maintainer scripts appear'
a,b=payload(newbase),payload(newmenu);assert not set(a)&set(b),'New package payloads overlap'
results=[]
def run(root,label,packages,expected=0):
 root.mkdir(parents=True,exist_ok=True)
 p=subprocess.run(['dpkg','--root='+str(root),'--no-triggers','--unpack',*[str(x) for x in packages]],text=True,capture_output=True)
 (out/(label+'.log')).write_text(p.stdout+p.stderr)
 assert p.returncode==expected,(label,p.returncode,p.stdout,p.stderr)
 results.append({'step':label,'exit_code':p.returncode,'expected':expected})
 if expected:assert 'kubabbar-glass-launcher.svg' in p.stderr and 'trying to overwrite' in p.stderr
 return p
# Reproduce the real machine's old-version upgrade collision first.
case=out/'case-old-upgrade';run(case,'old-install',[oldbase,oldmenu]);run(case,'bad-upgrade',[badbase],1)
run(case,'fixed-base-first',[newbase]);run(case,'fixed-menu-after',[newmenu])
# Also cover a machine which installed the first LC base without the optional variant.
case2=out/'case-base-lc';run(case2,'old-lc-base-alone',[badbase]);run(case2,'new-menu-first',[newmenu]);run(case2,'new-base-after',[newbase])
# Clean pair and both upgrade orders must retain every final file exactly.
case3=out/'case-clean';run(case3,'clean-pair',[newbase,newmenu])
for root in [case,case2,case3]:
 for relative,digest in (a|b).items():assert hashlib.sha256((root/relative).read_bytes()).hexdigest()==digest,(root,relative)
 p=subprocess.run(['dpkg-query','--admindir='+str(root/'var/lib/dpkg'),'-S','/usr/share/icons/hicolor/scalable/apps/kubabbar-glass-launcher.svg'],text=True,capture_output=True,check=True)
 assert p.stdout.startswith(menu+': ') and len(p.stdout.splitlines())==1,p.stdout
(out/'transition-checks.json').write_text(json.dumps({'state':'passed','scope':'Real dpkg unpack and ownership regression with original archives, both upgrade orders, clean pair, full final regular-file hashes. Dependency resolution is checked separately with APT; no dependency forcing or host package writes.','checks':results,'nonoverlapping_regular_files':len(a|b)},indent=2)+'\n')
print('PASS',len(results),'dpkg transitions; final files and exclusive ownership verified')
