#!/usr/bin/env python3
"""Rehearse the installed shader recovery in a disposable root, with exact hashes."""
from collections import defaultdict
import hashlib
import importlib.machinery
import importlib.util
import json
import lzma
from pathlib import Path
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

kit = (cfg.TREE / 'sparky-os')
sys.path.insert(0, str(kit))
loader = importlib.machinery.SourceFileLoader('dpkg_stereo_audit', str(kit / 'packages/dpkg-stereo/bin/dpkg-stereo'))
spec = importlib.util.spec_from_loader(loader.name, loader)
client = importlib.util.module_from_spec(spec)
loader.exec_module(client)
from lean.lang_c import GLSL_EXTS

base = (cfg.path('SPARKY_MIGRATION_WORK') / 'shader-upgrade-proof')
base.mkdir(exist_ok=True)
root = base / 'system'
root.mkdir(exist_ok=False)
host, target = client.Paths(), client.Paths(str(root))
host_records = client.Records(host)
selected = {p: r for p, r in host_records.items() if r['handler'] == 'c' and Path(p).suffix.lower() in GLSL_EXTS}
by_package = defaultdict(dict)
for path, record in selected.items():
    by_package[(record['package'], record['version'])][path] = record
    source = Path(path)
    destination = root / path[1:]
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
state = root / 'var/lib/dpkg-stereo'
(state / 'records').mkdir(parents=True)
(state / 'pristine').mkdir()
(root / 'var/lib/dpkg').mkdir(exist_ok=True)
shutil.copy2('/var/lib/dpkg/status', root / 'var/lib/dpkg/status')
for (package, _), rows in by_package.items():
    client.write_table(str(state / 'records' / (package + '.tsv')), client.FILE_COLS, rows)

reports = []
for (package, version), rows in by_package.items():
    originals = {}
    # The already authenticated FlightGear test data is large; use the retained
    # archive rather than downloading a second copy just to recover two shaders.
    if package == 'flightgear-data-base':
        cache = root / 'var/cache/apt/archives'
        cache.mkdir(parents=True, exist_ok=True)
        retained = (cfg.path('SPARKY_MIGRATION_WORK') / 'flightgear-data-inputs/flightgear-data-base_2024.1.5+dfsg-1_all.deb')
        (cache / 'flightgear-data-base_1%3a2024.1.5+dfsg-1_all.deb').symlink_to(retained)
        originals = client.deb_members(target, package, version, set(rows))
    else:
        originals = client.deb_members(host, package, version, set(rows))
    for path, row in rows.items():
        raw = originals.get(path)
        ok = raw is not None and hashlib.sha256(raw).hexdigest() == row['sha_orig']
        reports.append({'path': path, 'package': package, 'version': version,
                        'sha_orig': row['sha_orig'], 'recovered': ok})
        if ok:
            (state / 'pristine' / (row['sha_orig'] + '.xz')).write_bytes(lzma.compress(raw))
    print(package, sum(r['recovered'] for r in reports if r['package'] == package), len(rows), flush=True)
result = client.repair_consumers(target)
for row in reports:
    row['restored_matches'] = hashlib.sha256((root / row['path'][1:]).read_bytes()).hexdigest() == row['sha_orig']
report = {'host_changed': False, 'repair_exit': result, 'files': reports,
          'passed': result == 0 and all(row['restored_matches'] for row in reports)}
(base / 'comparison.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if report['passed'] else 1)
