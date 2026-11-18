#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Explain generated relation changes before exercising the installed upgrade."""
import argparse
import json
from pathlib import Path
import re
import subprocess
from inventory import paragraphs
from reconcile import write_tsv

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('stage', type=Path)
ap.add_argument('indexes', type=Path)
ap.add_argument('build', type=Path)
ap.add_argument('--output', type=Path, required=True)
a = ap.parse_args()
published = {}
for p in a.indexes.glob('Packages-*'):
    for row in paragraphs(p.read_text()):
        published[(row['Package'], row['Architecture'])] = row
changes, relation_rows, targets = [], [], []
for deb in sorted(a.stage.glob('*.deb')):
    new = paragraphs(subprocess.check_output(['dpkg-deb', '-f', str(deb)], text=True))[0]
    old = published.get((new['Package'], new['Architecture']), {})
    targets.append({'binary':new['Package'],'version':new['Version'],'architecture':new['Architecture'],
                    'published':old.get('Version','absent')})
    for field in ('Depends','Pre-Depends','Recommends','Suggests','Conflicts','Breaks','Replaces','Provides'):
        before = set(v.strip() for v in old.get(field, '').split(',') if v.strip())
        after = set(v.strip() for v in new.get(field, '').split(',') if v.strip())
        for kind, values in [('added', after-before), ('removed', before-after)]:
            for value in sorted(values):
                name = re.split(r'[ (|:]', value)[0]
                found = []
                for path in sorted((a.build/'sparky-os/lists').iterdir()):
                    if path.suffix not in ('.tsv','.list','.json','.py'):continue
                    for n,line in enumerate(path.read_text().splitlines(),1):
                        if re.search(r'(?<![\w-])'+re.escape(name)+r'(?![\w-])',line):
                            found.append(str(path.relative_to(a.build))+':'+str(n))
                if not found:found=['lists/make-meta.py generated package index/role/language relation']
                relation_rows.append({'binary':new['Package'],'field':field,'change':kind,'relation':value,'inputs':'; '.join(found)})
        if before != after:
            changes.append({'binary':new['Package'],'field':field,'published':old.get(field,''),'generated':new.get(field,'')})
write_tsv(a.output/'meta-relations.tsv',relation_rows,['binary','field','change','relation','inputs'])
write_tsv(a.output/'meta-fields.tsv',changes,['binary','field','published','generated'])
write_tsv(a.output/'meta-versions.tsv',targets,['binary','version','architecture','published'])
print(len(targets),'meta packages;',len(changes),'changed relation fields;',len(relation_rows),'added/removed relation entries')
