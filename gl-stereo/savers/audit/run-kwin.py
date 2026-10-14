# SPDX-License-Identifier: GPL-2.0-or-later
"""One compositor session per saver; collect evidence without promotion."""
import json
import os
from pathlib import Path
import subprocess
import signal
import shutil
import sys
root=Path(sys.argv[1]); root.mkdir(parents=True,exist_ok=False)
base=Path(__file__).resolve().parent
inventory=json.loads((base/'inventory-6.09.json').read_text())
names=sys.argv[2:] or [e['id'] for e in inventory if e['kind']=='hack']
results=[]
for name in names:
    directory=root/name
    with (root/(name+'.log')).open('w') as log:
        try:
            run=subprocess.Popen(['dbus-run-session','--','bash',str(base/'kwin-case.sh'),str(directory),name],stdout=log,stderr=log,start_new_session=True)
            try: run.wait(timeout=float(os.environ.get('AUDIT_TIMEOUT','40'))+40)
            except subprocess.TimeoutExpired:
                os.killpg(run.pid,signal.SIGKILL)
                run.wait()
                raise
            result={'id':name,'session_exit':run.returncode,'qualification':'pending'}
            if (directory/'result.json').exists(): result.update(json.loads((directory/'result.json').read_text()))
            with (directory/'depth-oracle.log').open('w') as depth:
                oracle=subprocess.run([sys.executable,str(base.parent.parent/'measure-hack.py'),str(directory)],stdout=depth,stderr=depth)
            result['depth_oracle']=oracle.returncode==0
            if oracle.returncode==0: result['depth']=json.loads((directory/'result.json').read_text())
        except Exception as error: result={'id':name,'error':str(error),'qualification':'pending'}
    # Each case has a fresh session; its shader/session caches are scratch.
    shutil.rmtree(directory/'home'/'.cache',ignore_errors=True)
    results.append(result)
    (root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(len(results),result['id'],result.get('session_exit'),result.get('depth_oracle'),flush=True)
