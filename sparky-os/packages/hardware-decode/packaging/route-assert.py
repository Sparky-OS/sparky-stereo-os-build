#!/usr/bin/env python3
"""Fail if a recorded decoder did not use the required hardware backend."""
import argparse,csv,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('trace',type=Path)
p.add_argument('expected',choices=('vaapi','cuda','software'))
a=p.parse_args()
rows=list(csv.reader(a.trace.read_text().splitlines()))
formats={r[2] for r in rows}
actual='vaapi' if formats=={'vaapi'} else 'cuda' if formats=={'cuda'} else 'software' if rows and all(r[7]=='0' for r in rows) else 'mixed'
print(f'expected {a.expected}, observed {actual}, formats {sorted(formats)}')
sys.exit(0 if actual==a.expected else 1)
