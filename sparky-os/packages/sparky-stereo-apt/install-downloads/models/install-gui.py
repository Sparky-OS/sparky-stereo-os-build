#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""The existing KDE debconf renderer, with the shared model install transaction."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
sys.path.insert(0,'/usr/lib/sparky-stereo-apt')
import sparky_install_downloads as notice


def main():
    data=json.loads(Path('/usr/share/sparky-install-models/messages.json').read_text())
    text=data.get(notice.language(),data['en'])
    if os.geteuid()!=0:
        print(text['root'],file=sys.stderr)
        return 1
    if len(sys.argv)!=2 or not re.fullmatch(r'[a-z0-9][a-z0-9-]*=[0-9][a-zA-Z0-9.+:~_-]*',sys.argv[1]):return 2
    name=sys.argv[1].split('=',1)[0]
    profile=Path('/usr/share/sparky-install-models/profiles')/(name+'.json')
    if profile.is_symlink() or json.loads(profile.read_text())['package']!=name:raise ValueError(name)
    env=dict(os.environ,DEBIAN_FRONTEND='passthrough',DEBIAN_PRIORITY='critical',CORE_FONTS_TITLE=json.loads(profile.read_text())['title'],CORE_FONTS_ACCEPT=text['accept'],CORE_FONTS_DECLINE=text['decline'])
    env.pop('DEBCONF_NONINTERACTIVE_SEEN',None)
    frontend=transaction=None
    with tempfile.TemporaryDirectory(prefix='sparky-model-consent-',dir='/run') as folder:
        env['DEBCONF_PIPE']=str(Path(folder)/'debconf')
        try:
            frontend=subprocess.Popen(['/usr/libexec/sparky-core-fonts-dialog',env['DEBCONF_PIPE']],env=env)
            deadline=time.monotonic()+10
            while not Path(env['DEBCONF_PIPE']).exists():
                if frontend.poll() is not None or time.monotonic()>deadline:raise RuntimeError('sparky-core-fonts-dialog')
                time.sleep(.05)
            transaction=subprocess.Popen(['/usr/bin/apt-get','-y','--no-remove','--no-allow-unauthenticated','-o','Dpkg::Use-Pty=0','install',sys.argv[1]],env=env,start_new_session=True)
            while transaction.poll() is None:
                if frontend.poll() is not None:raise RuntimeError('sparky-core-fonts-dialog')
                time.sleep(.1)
            return transaction.returncode
        finally:
            for process in [transaction,frontend]:
                if process is not None and process.poll() is None:
                    if process is transaction:os.killpg(process.pid,signal.SIGTERM)
                    else:process.terminate()
                    try:process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        if process is transaction:os.killpg(process.pid,signal.SIGKILL)
                        else:process.kill()
                        process.wait()


if __name__=='__main__':
    try:sys.exit(main())
    except Exception as error:
        data=json.loads(Path('/usr/share/sparky-install-models/messages.json').read_text());text=data.get(notice.language(),data['en'])
        print(text['failed'].format(reason=str(error)),file=sys.stderr)
        sys.exit(1)
