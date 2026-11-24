# SPDX-License-Identifier: GPL-2.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
from pathlib import Path
import json,re,sys
out=Path(sys.argv[1]);log=(out/'kamoso.log').read_text(errors='replace')
children={c:p for c,p in re.findall(r'get_subsurface\(new id wl_subsurface#\d+, wl_surface#(\d+), wl_surface#(\d+)\)',log)}
objects={o:s for o,s in re.findall(r'create\(new id kde_stereo_content_v1#(\d+), wl_surface#(\d+)\)',log)}
ids=re.findall(r'kde_stereo_content_v1#(\d+)\.set_content\(3\)',log)
spec=json.loads((out/'spec.json').read_text());surfaces=[objects.get(i) for i in ids]
expected=1 if spec['stereo'] else 0
passed=len(surfaces)==expected and all(s in children and children[s] not in surfaces for s in surfaces)
row=dict(expected=expected,found=len(surfaces),declaredSurfaces=surfaces,children=children,passed=passed)
(out/'child-declaration.json').write_text(json.dumps(row,indent=2));print(json.dumps(row));sys.exit(not passed)
