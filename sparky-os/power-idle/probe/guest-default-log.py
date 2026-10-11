#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check quiet default logs and measure CPU of the idle production guest service."""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('output',type=Path)
p.add_argument('--seconds',type=int,default=20)
a=p.parse_args()
r={'verified':False,'failure':None}
status=0
try:
    assert os.geteuid()==0 and not Path('/.dockerenv').exists()
    subprocess.run(['systemd-detect-virt','--vm'],check=True,capture_output=True)
    pid=int(subprocess.check_output(['systemctl','show','cushion-swap','-p','MainPID','--value']))
    assert pid>0
    log=Path('/var/log/cushion-swap/cushion-swap.log')
    def cpu():
        fields=Path(f'/proc/{pid}/stat').read_text().split(') ',1)[1].split()
        return sum(int(fields[n]) for n in (11,12))
    start=time.time()
    bytes0=log.stat().st_size
    cpu0=cpu()
    time.sleep(a.seconds)
    cpu1=cpu()
    bytes1=log.stat().st_size
    journal=subprocess.check_output(['journalctl',f'_PID={pid}','--since',f'@{int(start)}',
        '-q','--no-pager','-o','cat'],text=True)
    r.update({'seconds':a.seconds,'log_bytes':[bytes0,bytes1],'daemon_journal':journal,
        'cpu_percent_core':(cpu1-cpu0)/os.sysconf('SC_CLK_TCK')/a.seconds*100,
        'state':Path('/run/cushion-swap/status').read_text()})
    assert bytes0==bytes1 and not journal.strip(), 'idle default produced routine logs'
    assert 'CALIBRATED=yes' in r['state']
    r['verified']=True
except Exception as error:
    r['failure']=str(error)
    status=1
a.output.write_text(json.dumps(r,indent=2)+'\n')
raise SystemExit(status)
