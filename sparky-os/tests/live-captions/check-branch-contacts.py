#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Audit added address-shaped strings in the complete branch diff from BASE."""
import json,re,subprocess,sys
repo,base=sys.argv[1:3]
diff=subprocess.check_output(['git','-C',repo,'diff','--unified=0',base,'HEAD'],text=True)
rows=[];path='';line_number=0
for line in diff.splitlines():
    if line.startswith('+++ b/'):path=line[6:]
    elif line.startswith('@@'):
        line_number=int(re.search(r'\+(\d+)',line).group(1))-1
    elif line.startswith('+'):
        line_number+=1
        for match in re.finditer(r'[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',line[1:]):
            address=match.group(0);allowed=address=='Capitain_Jack@yahoo.com'
            rows.append(dict(file=path,line=line_number,match=address if allowed else '[third-party contact]',decision='keep Daniel packaging identity' if allowed else 'remove contact, keep author name',passed=allowed))
    elif not line.startswith('-'):line_number+=1
print(json.dumps(rows,indent=2))
sys.exit(0 if all(x['passed'] for x in rows) else 1)
