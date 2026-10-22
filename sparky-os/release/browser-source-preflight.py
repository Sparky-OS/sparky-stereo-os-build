#!/usr/bin/env python3
"""Read-only checks of not-yet-qualified browser inputs; collect all failures."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json,sys
sys.dont_write_bytecode = True
root=Path(sys.argv[1]);output=Path(sys.argv[2]);names=json.loads(Path(sys.argv[3]).read_text())
sys.path.insert(0,str(root/'debian/sparky-lean-toolkit'))
from lean import project

def check(name):
    result=project.project('/'+name,(root/name).read_bytes(),package='native-build',pointer=False)
    return {'path':name,'status':result.status,'reason':result.reason}
rows=[]
with ThreadPoolExecutor(max_workers=4) as pool:
    for result in pool.map(check,names):
        rows.append(result)
        if result['reason'].startswith(('check failed:','the c reader','the java reader','not stable')):print(json.dumps(result),flush=True)
failures=[r for r in rows if r['reason'].startswith(('check failed:','the c reader','the java reader','not stable'))]
output.write_text(json.dumps({'files':len(rows),'failures':failures,'results':rows},indent=2)+'\n')
print('Read-only checks',len(rows),'failures',len(failures))
raise SystemExit(bool(failures))
