# SPDX-License-Identifier: GPL-2.0-or-later
from pathlib import Path
import json,sys
from measure import pair,shift
root=Path(sys.argv[1]);rows=json.loads((root/'predictions.json').read_text())
for row in rows:
 a,b=pair(root/f"{row['id']}-{row['size']}.pns")
 error,dx,dy=shift(a,b)
 assert (dx,dy)==(row['expected'],0) and error<.01,(row,error,dx,dy)
 row.update(measured=dx,vertical=dy,squaredError=error)
print(json.dumps(rows,indent=2))
