#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""Real debconf re-execution must not interpret human notices as commands."""
import hashlib,json,os,subprocess,sys,tempfile,shutil
from pathlib import Path
if os.geteuid()!=0:raise SystemExit('Run only in a disposable package test container as root')
name='sp501-own-postinst-fixture';data=Path('/usr/share/sparky-install-models')
profile=data/'profiles'/(name+'.json');licence=data/'licences'/(name+'.txt')
for folder in [profile.parent,licence.parent]:folder.mkdir(parents=True,exist_ok=True)
body=b'Our own generated fixture terms. No third-party model or acceptance.\n'
root=Path('/var/lib')/name
assert not root.exists() and not profile.exists() and not licence.exists()
licence.write_bytes(body)
record=dict(id=name,package=name,title='Our fixture',root=str(root),family='fixture',group=name,version='1',consent_required=True,purge_removes_models=True,download_bytes=1,files=[dict(file='never-downloaded.bin',url='https://invalid.example/fixture',bytes=1,sha256=hashlib.sha256(b'x').hexdigest())],licences=[dict(name='Own fixture',file=licence.name,url='https://invalid.example/terms',sha256=hashlib.sha256(body).hexdigest())])
profile.write_text(json.dumps(record))
try:
 with tempfile.TemporaryDirectory(prefix='sp501-postinst-',dir='/run') as work:
  program=Path(work)/'postinst';shutil.copyfile(sys.argv[1],program);program.chmod(0o755)
  template=Path(work)/'postinst.templates';template.write_text('Template: '+name+'/licence\nType: note\nDescription: Our fixture\n Our own generated fixture terms.\n\nTemplate: '+name+'/consent\nType: boolean\nDefault: false\nDescription: Accept our own fixture?\n')
  result=subprocess.run([str(program),'configure'],env=dict(os.environ,DPKG_MAINTSCRIPT_PACKAGE=name,DEBIAN_FRONTEND='noninteractive',DEBCONF_DEBUG='developer',LANGUAGE='en',LC_ALL='C.UTF-8'),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30)
 print(result.stdout)
 assert result.returncode!=0,result.returncode
 assert 'Unsupported command' not in result.stdout,result.stdout
 assert 'Licence not accepted; no models were downloaded.' in result.stdout,result.stdout
 assert not root.exists()
 print('PASS real debconf protocol, default No, no fixture body requested')
finally:
 profile.unlink(missing_ok=True);licence.unlink(missing_ok=True)
