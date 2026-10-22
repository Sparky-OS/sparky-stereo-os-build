#!/usr/bin/env python3
"""Retain browser proofs and remove only its qualified migration build tree."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tarfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
work = base / 'jobs/sparky-stereo-browser-amd64'
source = base / 'browser-source/source'
sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

status = json.loads((work / 'status.json').read_text())
runtime = json.loads((base / 'browser-installed-check/status.json').read_text())
assert status['state'] == 'candidate-needs-review' and status['exit_code'] == 0
assert runtime['state'] == 'passed' and runtime['passed'] and runtime['cases'] == 77
assert (base / 'browser-installed-check/capture-review.json').is_file()
assert source.is_dir() and not source.is_symlink()
assert source.resolve() == source
assert not (work / 'build-tree-retention.json').exists()

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

descriptors = list(work.glob('*.dsc'))
assert len(descriptors) == 1
descriptor = descriptors[0]
assert sha(descriptor) == status['source_descriptor_sha256']
retained = {descriptor.name: sha(descriptor)}
fields = next(stanzas(descriptor.read_text()))
for row in fields['checksums-sha256'].splitlines():
    if not row.strip():
        continue
    expected, size, filename = row.split()
    path = work / filename
    assert path.parent == work and path.stat().st_size == int(size)
    assert sha(path) == expected
    retained[filename] = expected
for filename in status['archives'] + ['native-source.json', 'native-authored-evidence.tar.xz',
                                      'resume-cargo.log', 'resume-cargo.sh']:
    retained[filename] = sha(work / filename)
native = json.loads((work / 'native-source.json').read_text())
assert native['qualified'] and native['stage'] == 'before compilation'
assert (source / '.sparky-lc/source.json').read_bytes() == (work / 'native-source.json').read_bytes()
spec = importlib.util.spec_from_file_location('compiler_inputs', (cfg.TREE / 'sparky-os/release/collect-compiler-inputs.py'))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
observed = collector.collect(source, work / 'compiler-input-evidence.json')
archive = work / 'compiler-dependencies.tar.gz'
with tarfile.open(archive, 'x:gz', compresslevel=1) as tar:
    for row in observed['dependency_evidence']:
        path = source / row['path']
        assert sha(path) == row['sha256']
        tar.add(path, arcname=row['path'], recursive=False)
retained[archive.name] = sha(archive)
retained['compiler-input-evidence.json'] = sha(work / 'compiler-input-evidence.json')
(work / 'build-tree-retention.json').write_text(json.dumps(dict(
    source=str(source), retained_archives_sha256=retained,
    installed_qualification=str(base / 'browser-installed-check'),
    action='Remove only expanded migration source/object tree; keep accepted upstream source and compilers'),
    indent=2) + '\n')
shutil.rmtree(source)
print('Browser migration build tree retired after installed and capture qualification', flush=True)
