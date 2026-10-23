#!/usr/bin/env python3
"""Stage the verified cohort without modifying a published archive."""
import argparse, hashlib, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('work',type=Path)
p.add_argument('package')
a=p.parse_args()
job=a.work/'jobs'/a.package
for name in ('check-debs.log','check-link.log'):
    assert (job/name).is_file(), name
out=a.work/'out'/a.package
out.mkdir(parents=True,exist_ok=True)
import json
predecessor=json.loads((job/'predecessor.json').read_text()).get('dsc') if (job/'predecessor.json').exists() else None
new_sources=[d for d in job.glob('*.dsc') if d.name!=predecessor]
assert len(new_sources)==1, new_sources
source_files={new_sources[0].name}
for line in new_sources[0].read_text().split('Checksums-Sha256:\n',1)[1].splitlines():
    if not line.startswith(' '):break
    source_files.add(line.split()[-1])
for f in sorted(job.iterdir()):
    if f.is_file() and (f.name in source_files or f.suffix in ('.deb','.changes','.buildinfo')):
        shutil.copy2(f,out/f.name)
for f in out.glob('*.deb'):
    shutil.copy2(f,a.work/'new'/f.name)
(out/'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.name}\n' for f in sorted(out.iterdir()) if f.is_file() and f.name!='SHA256SUMS'))
with (a.work/'new/Packages').open('w') as stream:
    subprocess.run(['dpkg-scanpackages','--multiversion','.','/dev/null'],cwd=a.work/'new',stdout=stream,check=True)
print(out)
