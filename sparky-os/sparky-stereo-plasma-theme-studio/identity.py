# SPDX-License-Identifier: GPL-2.0-or-later
"""Project identity is data, shared by C++, desktop metadata and catalogues."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
i=json.loads((a.source/'identity.json').read_text());a.output.mkdir(parents=True,exist_ok=True)
header='#pragma once\n#include <QString>\nnamespace Identity {\n'
for k,v in i.items():header+=f'inline QString {k}() {{ return QString::fromUtf8({json.dumps(v,ensure_ascii=False)}); }}\n'
(a.output/'identity.h').write_text(header+'}\n')
for name in ['share/'+i['package']+'.desktop.in','share/'+i['package']+'.1.in']:
 s=(a.source/name).read_text()
 for k,v in i.items():s=s.replace('@'+k.upper()+'@',v)
 (a.output/Path(name).name.removesuffix('.in')).write_text(s)
for f in (a.source/'lang').glob('*.ts'):
 out=a.output/'lang'/f.name;out.parent.mkdir(exist_ok=True)
 out.write_text(f.read_text().replace('@PRODUCT@',i['product']))
