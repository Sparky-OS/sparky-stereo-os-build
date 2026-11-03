#!/usr/bin/python3
"""Exercise the real guard against private apt/config fixtures; never touch swap."""
from pathlib import Path
import subprocess
import sys
import tempfile

source=Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory)
    paths=['/var/lib/sparky-stereo-kernel-settings','/var/lib/apt/extended_states',
           '/etc/default/sparky-stereo-zram','/run/sparky-stereo-kernel-settings/blocked-zram0',
           '/etc/apt/apt.conf.d/90sparky-stereo-chosen-zram']
    code=source.read_text()
    for path in paths:
        code=code.replace(path,str(root)+path)
        (root/path.lstrip('/')).parent.mkdir(parents=True,exist_ok=True)
    query=root/'dpkg-query'
    query.write_text('#!/bin/sh\n[ "$3" = zram-tools ] && [ -f "'+str(root)+'/tools-installed" ] && { printf installed; exit 0; }\nexit 1\n')
    query.chmod(0o755)
    code=code.replace('/usr/bin/dpkg-query',str(query))
    helper=root/'helper.py';helper.write_text(code)
    state=root/'var/lib/sparky-stereo-kernel-settings';state.mkdir(exist_ok=True)
    apt=root/'var/lib/apt/extended_states'
    config=root/'etc/default/sparky-stereo-zram'
    blocked=root/'run/sparky-stereo-kernel-settings/blocked-zram0'
    marker=state/'leftover-zram-generator'
    automatic='Package: systemd-zram-generator\nArchitecture: amd64\nAuto-Installed: 1\n\n'
    def check(name,expected):
        result=subprocess.run([sys.executable,str(helper),'--allow'])
        assert result.returncode==expected,(name,result.returncode,expected)
        assert blocked.exists()==(expected==1),name
        print(f'PASS {name}: exit={result.returncode}, blocked={blocked.exists()}')
    apt.write_text(automatic)
    check('no edition migration marker',0)
    marker.touch()
    for choice in (None,'auto','off'):
        if choice is None: config.unlink(missing_ok=True)
        else: config.write_text('ZRAM='+choice+'\n')
        check('leftover '+str(choice),1)
        check('next setup '+str(choice),1)
    config.write_text('ZRAM="on" # previous explicit choice\n')
    check('previous On',0)
    config.write_text('ZRAM=off\n')
    apt.write_text('')
    check('apt install marks generator manual',0)
    apt.write_text(automatic)
    (root/'tools-installed').touch()
    check('manually installed zram-tools',0)
    apt.write_text(automatic+'Package: zram-tools\nAuto-Installed: 1\n\n')
    check('both automatic are not a person choice',1)
print('PASS all migration choices')
