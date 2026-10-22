#!/usr/bin/env python3
"""Verify every source archive named by the candidate source-coverage inventory."""
from pathlib import Path
import hashlib
import json
import sys
from datetime import datetime, timezone
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

coverage = json.loads((notes / 'candidate-source-coverage.json').read_text())
assert not coverage['missing'] and not coverage['descriptor_collisions']
rows, cache, errors = [], {}, []
for group in coverage['matched']:
    path = Path(group['descriptor'])
    text = path.read_text()
    if text.startswith('-----BEGIN PGP SIGNED MESSAGE-----'):
        text = text.split('\n\n', 1)[1].split('\n-----BEGIN PGP SIGNATURE-----', 1)[0]
        text = '\n'.join(line[2:] if line.startswith('- ') else line for line in text.splitlines())
    fields = next(row for row in stanzas(text) if 'source' in row and 'version' in row)
    assert fields['source'] == group['source'] and fields['version'] == group['version']
    archives = []
    for line in fields['checksums-sha256'].splitlines():
        if not line.strip():
            continue
        expected, size, name = line.split()
        assert Path(name).name == name and name not in ['.', '..'], name
        archive = path.parent / name
        if not archive.is_file():
            errors.append(dict(path=str(archive), error='missing'))
            continue
        stat = archive.stat()
        key = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns)
        if key not in cache:
            with archive.open('rb') as stream:
                cache[key] = hashlib.file_digest(stream, 'sha256').hexdigest()
            after = archive.stat()
            assert (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns) == (
                stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns), \
                'Source changed during verification'
        actual = cache[key]
        passed = actual == expected and stat.st_size == int(size)
        record = dict(path=str(archive), sha256=actual, size=stat.st_size, passed=passed)
        archives.append(record)
        if not passed:
            errors.append(record)
    rows.append(dict(source=group['source'], version=group['version'], descriptor=str(path),
        descriptor_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), archives=archives))
report = dict(time=datetime.now(timezone.utc).isoformat(),
    scope='candidate source archive hashes; no dependency or runtime qualification',
    source_groups=len(rows), unique_archive_files=len(cache), errors=errors, sources=rows)
(notes / 'candidate-source-archive-bytes.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items() if key != 'sources'}, indent=2))
raise SystemExit(bool(errors))
