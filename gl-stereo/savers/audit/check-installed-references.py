#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare a package's current composed eyes with stored independent cameras."""
import json
from pathlib import Path
import subprocess
import sys
base=Path(__file__).resolve().parent
reference=Path(sys.argv[1]); actual=Path(sys.argv[2]); output=Path(sys.argv[3])
result=subprocess.check_output([sys.executable,str(base/'compare-reference.py'),str(reference),str(actual)],text=True)
items=json.loads(result)
output.write_text(json.dumps(items,indent=2)+'\n')
assert items and all(item['passed'] for item in items)
