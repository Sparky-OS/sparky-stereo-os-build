#!/usr/bin/env python3
"""Summarize retained observations from completed, current native candidates."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
base = (cfg.path('SPARKY_MIGRATION_WORK') / 'jobs')
rows = []
for path in sorted(base.glob('*/compiler-input-evidence.json')):
    if '-attempt' in path.parent.name or '-engine' in path.parent.name:
        continue
    status = json.loads((path.parent / 'status.json').read_text())
    assert status['state'] == 'candidate-needs-review' and status['exit_code'] == 0
    proof = json.loads(path.read_text())
    assert not proof['performance_claim']
    row = dict(job=path.parent.name, files=len(proof['files']),
               evidence=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    row.update({key: proof[key] for key in ['authored_bytes', 'compiler_input_bytes', 'bytes_removed']})
    assert row['authored_bytes'] - row['compiler_input_bytes'] == row['bytes_removed']
    rows.append(row)
totals = {key: sum(row[key] for row in rows)
          for key in ['files', 'authored_bytes', 'compiler_input_bytes', 'bytes_removed']}
report = dict(time=datetime.now(timezone.utc).isoformat(),
    scope='Only retained actual compiler-dependency evidence; unique files within each build, '
          'summed across builds/architectures. Not physical I/O, repeated parses, timing or '
          'runtime savings. Zero observed inputs means unavailable evidence, not zero savings.',
    totals=totals, sources=rows)
(notes / 'observed-compiler-inputs-checkpoint.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(dict(builds=len(rows), totals=totals, scope=report['scope']), indent=2))
