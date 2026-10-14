#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Select completed installed captures and evaluate their independent controls."""
import json
from pathlib import Path
import shutil
import subprocess
import sys

root=Path(sys.argv[1]); tools=Path(__file__).resolve().parent
inventory=json.loads((root/'installed-inventory.json').read_text())
names=[entry['id'] for entry in inventory if entry['kind']=='hack']
selected={name:'installed-kwin/'+name for name in names}
for name in ('chompytower','energystream','companioncube'):
    selected[name]='installed-warmup/'+name
for name in ('starwars','fliptext'):
    selected[name]='installed-'+name+'/'+name
selected['fliptext']='installed-fliptext-final2/fliptext'
selected['flurry']='installed-flurry/flurry'
for name,directory in selected.items():
    case=root/directory
    assert (case/'execution.json').is_file(),(name,'missing installed capture')
(root/'installed-selected-cases.json').write_text(json.dumps(selected,indent=2)+'\n')

# Stable independent goldens are valid for these unchanged XScreenSaver ELFs.
# Text cases have new references made in the installed package environment.
references=root/'installed-reference-selected'
references.mkdir(exist_ok=True)
for case in (root/'reference-final').iterdir():
    if case.is_dir():
        target=references/case.name
        if not target.exists():target.symlink_to(case, target_is_directory=True)
for name,prefix in [('energystream','reference-energy'),('starwars','installed-starwars-reference'),('fliptext','installed-fliptext-final2-reference'),('flurry','installed-flurry-reference')]:
    case=references/name;case.mkdir(exist_ok=True)
    for eye in ('left','right'):
        target=case/eye
        if target.is_symlink():target.unlink()
        target.symlink_to(root/(prefix+'-'+eye)/name,target_is_directory=True)

def check(script,output,*arguments):
    result=subprocess.run([sys.executable,str(tools/script),*map(str,arguments)],capture_output=True,text=True)
    (root/output).write_text(result.stdout)
    assert result.returncode==0,(script,result.stderr)
    items=json.loads(result.stdout)
    assert items and all(item['passed'] for item in items),(script,[item for item in items if not item['passed']])
    return items

actual=root/'installed-selected';actual.mkdir(exist_ok=True)
for name,directory in selected.items():
    target=actual/name
    if target.is_symlink():target.unlink()
    target.symlink_to(root/directory,target_is_directory=True)
check('compare-reference.py','installed-reference-checked.json',references,actual)
check('check-flat.py','installed-flat-checked.json',actual)
check('compare-composed.py','installed-composition-checked.json',actual)
print('PASS: selected',len(selected),'installed captures and checked reference, flat and compositor controls')
