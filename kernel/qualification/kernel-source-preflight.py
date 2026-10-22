#!/usr/bin/env python3
"""Collect native-consumer failures from the retained base-kernel source, read-only."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import fnmatch,json,sys,time
sys.dont_write_bytecode=True
root=Path('/source');sys.path.insert(0,str(root/'debian/sparky-lean-toolkit'))
from lean import project,source_tree
plan=source_tree.preservation_plan(root);names=[];left=0
for p in sorted(root.rglob('*')):
 rel=p.relative_to(root);name=rel.as_posix()
 if p.is_symlink() or not p.is_file() or p.suffix.lower() not in source_tree.lang_c.EXTS or any(x in source_tree.EXCLUDED or x.startswith('obj-') for x in rel.parts):continue
 if any(fnmatch.fnmatchcase(name,pat) for pat in plan):left+=1
 else:names.append(name)

def check(name):
 r=project.project('/'+name,(root/name).read_bytes(),package='native-build',pointer=False)
 return {'path':name,'status':r.status,'reason':r.reason}
rows=[];begin=time.time()
with ThreadPoolExecutor(max_workers=4) as pool:
 for r in pool.map(check,names):
  rows.append(r)
  if r['reason'].startswith(('check failed:','the c reader','the java reader','not stable')):print(json.dumps(r),flush=True)
failures=[r for r in rows if r['reason'].startswith(('check failed:','the c reader','the java reader','not stable'))]
Path('/evidence/result.json').write_text(json.dumps({'scope':'read-only preflight; no native build or package qualification','files_checked':len(rows),'preserved_by_plan':left,'seconds':time.time()-begin,'failures':failures,'results':rows},indent=2)+'\n')
print('Preflight',len(rows),'files',left,'preserved',len(failures),'failures',flush=True)
raise SystemExit(bool(failures))
