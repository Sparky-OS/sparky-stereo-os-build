#!/usr/bin/env python3
"""Record staged migration coverage without treating candidates as releases."""
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

initial = json.loads((notes / "current-packages.json").read_text())
if isinstance(initial, dict):
    raise SystemExit("Review changed starting inventory schema")
identities = {(r["Package"], r["Architecture"]) for r in initial}
unmarked = {(r["Package"], r["Architecture"]) for r in initial
            if not r.get("Sparky-Lean-Code", "").startswith("lc1 ")}
replacements = json.loads((notes / 'package-replacements.json').read_text())
replacement_map = {(r['replacement'], r['architecture']): r for r in replacements}
assert len(replacement_map) == len(replacements)
assert all((r['original'], r['architecture']) in identities for r in replacements)
statuses = []
archives = []
for work in sorted((base / "jobs").iterdir()):
    if "-attempt" in work.name or "-engine018" in work.name:
        continue
    status = work / "status.json"
    if not status.exists():
        continue
    row = json.loads(status.read_text())
    statuses.append(row)
    if row["state"] == "candidate-needs-review":
        archives.extend(work.glob("*+lc1_*.deb"))
for category in ("tooling", "skills", "meta", "scripts"):
    archives.extend((base / category).glob("*.deb"))
    if category == "scripts":
        # Standalone builders keep each source and its binaries together.
        for work in (base / category).iterdir():
            if not work.is_dir() or '-attempt' in work.name:
                continue
            status = work / 'status.json'
            if status.exists() and json.loads(status.read_text())['state'] != 'candidate-needs-review':
                continue
            archives.extend(work.glob('*.deb'))

records = []
covered = set()
covered_replacements = []
for archive in sorted(archives):
    output = subprocess.check_output([
        "dpkg-deb", "-f", str(archive), "Package", "Version", "Architecture",
        "Sparky-Lean-Code",
    ], text=True)
    fields = next(stanzas(output))
    if not fields.get("sparky-lean-code", "").startswith("lc1 "):
        continue
    row = {key: fields[key.lower()] for key in (
        "Package", "Version", "Architecture", "Sparky-Lean-Code")}
    row["archive"] = str(archive)
    records.append(row)
    identity = row["Package"], row["Architecture"]
    if identity in identities:
        covered.add(identity)
    if identity in replacement_map:
        replacement = replacement_map[identity]
        assert row['Version'] == replacement['replacement_version']
        covered.add((replacement['original'], replacement['architecture']))
        covered_replacements.append(replacement)

report = {
    "time": datetime.now(timezone.utc).isoformat(),
    "status": "candidates only, not published or installed; coverage is not release qualification",
    "candidate_current_identities": len(covered),
    "candidate_originally_unmarked_identities": len(covered & unmarked),
    "original_unmarked": len(unmarked),
    "job_states": dict(Counter(r["state"] for r in statuses)),
    "failed_native_jobs": [r for r in statuses if r["state"] != "candidate-needs-review"],
    "candidate_archives": len(records),
    "covered_replacements": covered_replacements,
    "covered": sorted(covered),
    "archives": records,
}
(notes / "migration-progress.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({k: v for k, v in report.items() if k not in ("archives", "covered")}, indent=2))
