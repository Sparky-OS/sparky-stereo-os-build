#!/usr/bin/env python3
"""Select immutable release inputs; stage only after migration qualification.

Default is a private JSON plan. --stage creates hardlinks in a fresh scratch
directory. Neither mode publishes, signs, changes APT or installs packages.
Run checkpoint.py and audit-candidate-sources.py before using this script.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
original = cfg.path('SPARKY_REPO_DIR')
sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--stage', action='store_true')
args = parser.parse_args()


def read(path):
    return json.loads(path.read_text())


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fields(text):
    if text.startswith('-----BEGIN PGP SIGNED MESSAGE-----'):
        text = text.split('\n\n', 1)[1].split('\n-----BEGIN PGP SIGNATURE-----', 1)[0]
        text = '\n'.join(line[2:] if line.startswith('- ') else line for line in text.splitlines())
    return next(stanzas(text))


def retain(source, target, digest):
    """Hardlink on one filesystem, copy across devices, never replace a file."""
    if target.exists():
        assert sha(target) == digest, ('Conflicting retained filename', target)
        return
    if source.stat().st_dev == target.parent.stat().st_dev:
        try:
            os.link(source, target)
        except PermissionError:
            # Container-built archives may be root-owned. Keep ownership and
            # bytes intact; protected_hardlinks requires privilege for this link.
            subprocess.run(['sudo', '-n', 'ln', '--', str(source), str(target)], check=True)
    else:
        import shutil
        with target.open('xb') as output, source.open('rb') as stream:
            shutil.copyfileobj(stream, output)
    assert sha(target) == digest


progress = read(notes / 'migration-progress.json')
coverage = read(notes / 'candidate-source-coverage.json')
initial = read(notes / 'current-packages.json')
paths = {Path(row['archive']) for row in progress['archives']}
paths.update(original / row['Filename'] for row in initial
             if row.get('Sparky-Lean-Code', '').startswith('lc1 '))
selected, identities = {}, {}
for path in sorted(paths):
    control = fields(subprocess.check_output(['dpkg-deb', '-f', str(path)], text=True))
    package, version, arch = (control[key] for key in ['package', 'version', 'architecture'])
    assert control.get('sparky-lean-code', '').startswith('lc1 '), path
    assert arch in ['all', 'amd64', 'i386', 'arm64'], path
    digest = sha(path)
    identity = package, version, arch
    assert identities.setdefault(identity, digest) == digest, ('Conflicting binary identity', identity)
    key = package, arch
    old = selected.get(key)
    if old and subprocess.run(['dpkg', '--compare-versions', version, 'le', old['version']]).returncode == 0:
        continue
    source = control.get('source', package)
    selected[key] = dict(package=package, version=version, architecture=arch,
                         archive=str(path), sha256=digest,
                         source=source.split()[0],
                         source_version=source.split('(', 1)[1].rstrip(')') if '(' in source else version)

replacements = read(notes / 'package-replacements.json')
covered_originals = set(selected)
for row in replacements:
    key = row['replacement'], row['architecture']
    if key in selected and selected[key]['version'] == row['replacement_version']:
        old = row['original'], row['architecture']
        covered_originals.add(old)
        selected.pop(old, None)
missing = sorted({(row['Package'], row['Architecture']) for row in initial} - covered_originals)
descriptors = {(row['source'], row['version']): Path(row['descriptor']) for row in coverage['matched']}
sources = {}
for row in selected.values():
    key = row['source'], row['source_version']
    assert key in descriptors, ('Missing source descriptor', key)
    if key in sources:
        continue
    descriptor = descriptors[key]
    control = fields(descriptor.read_text())
    assert (control['source'], control['version']) == key
    files = [dict(path=str(descriptor), sha256=sha(descriptor))]
    for line in control['checksums-sha256'].splitlines():
        if not line.strip():
            continue
        digest, size, filename = line.split()
        assert Path(filename).name == filename
        path = descriptor.parent / filename
        assert path.stat().st_size == int(size) and sha(path) == digest, path
        files.append(dict(path=str(path), sha256=digest))
    sources[key] = dict(source=key[0], version=key[1], files=files)

gaps = []
if missing:
    gaps.append(f'{len(missing)} original package/architecture identities still lack an LC candidate')
if progress['failed_native_jobs']:
    gaps.append('Native jobs are unfinished; consult migration-progress.json')
if coverage['missing'] or coverage['descriptor_collisions']:
    gaps.append('Source identity audit is incomplete or conflicting')
for name in ['mesa', 'wine', 'abseil']:
    twin = base / 'logs' / ('multiarch-' + name + '.json')
    if not twin.exists() or not read(twin) or any(row['different'] for row in read(twin)):
        gaps.append(f'{name}: matching-source Multi-Arch shared-file check not completed')
    else:
        for proof in read(twin):
            for arch in ['amd64', 'i386']:
                candidate = selected.get((proof['package'], arch))
                if not candidate or candidate['version'] != proof['version']:
                    gaps.append(f'{name}: shared-file evidence does not match selected {proof["package"]}:{arch}')
        primary = base / 'jobs' / (name + '-amd64')
        secondary = base / 'jobs' / (name + '-i386')
        descriptors_for_twin = list(primary.glob('*+lc1.dsc'))
        if (len(descriptors_for_twin) != 1
                or sha(descriptors_for_twin[0]) != read(secondary / 'status.json').get('source_descriptor_sha256')):
            gaps.append(f'{name}: current twins do not identify the same retained source')
selected_hashes = {row['sha256'] for row in selected.values()}
qemu_proof = base / 'qemu-installed-check'
if not (qemu_proof / 'status.json').exists() or not read(qemu_proof / 'status.json').get('passed'):
    gaps.append('Installed QEMU qualification not completed')
else:
    inputs = read(qemu_proof / 'input-packages.json')
    if len(inputs) != 4 or any(row['sha256'] not in selected_hashes for row in inputs):
        gaps.append('Installed QEMU qualification is for other package bytes')
    if not (qemu_proof / 'payload-check.json').exists() or not read(qemu_proof / 'payload-check.json').get('passed'):
        gaps.append('Installed QEMU payload verification not completed')
for flavour in ['base', 'v3', 'rt']:
    qualification = base / 'kernel-qualification' / flavour
    for filename in ['status.json', 'dkms-status.json']:
        path = qualification / filename
        if not path.exists() or read(path).get('state') != 'passed':
            gaps.append(f'Kernel {flavour}: {filename} not passed')
    compat_proof = qualification / 'dkms-inputs/compat-package.json'
    compat_selected = selected.get(('sparky-stereo-dkms-compat', 'all'))
    if (not compat_proof.exists() or not compat_selected
            or read(compat_proof)['sha256'] != compat_selected['sha256']):
        gaps.append(f'Kernel {flavour}: compatibility package proof does not match selection')
    cases = qualification / 'dkms-inputs/cases.json'
    if not cases.exists() or any(case.get('archive_sha256') not in selected_hashes
                                for case in read(cases) if 'archive_sha256' in case):
        gaps.append(f'Kernel {flavour}: module package proof does not match selection')
    inputs = qualification / 'inputs.json'
    if inputs.exists():
        proof = read(inputs)
        if proof['rehearsal'] or any(row['sha256'] not in selected_hashes for row in proof['archives'].values()):
            gaps.append(f'Kernel {flavour}: qualification is for other package bytes')
        if proof['settings_sha256'] not in selected_hashes:
            gaps.append(f'Kernel {flavour}: tested settings package is not selected')
    else:
        gaps.append(f'Kernel {flavour}: qualification inputs absent')
browser = base / 'browser-installed-check/status.json'
if not browser.exists() or read(browser).get('state') != 'passed':
    gaps.append('Installed browser checks and representative capture review not completed')
else:
    browser_inputs = read(browser.with_name('inputs.json'))
    candidate = selected.get(('sparky-stereo-browser', 'amd64'))
    if not candidate or candidate['sha256'] != browser_inputs['sha256']:
        gaps.append('Installed browser proof is for other package bytes')
    if not browser.with_name('capture-review.json').is_file():
        gaps.append('Browser capture review is missing')
for row in selected.values():
    if row['source'] == 'sparky-stereo-meta' and subprocess.run(
            ['dpkg', '--compare-versions', row['source_version'], 'lt', '20261020.1']).returncode == 0:
        gaps.append('Final metapackages must resolve against build-9 kernels and current candidates')
        break

report = dict(time=datetime.now(timezone.utc).isoformat(),
              scope='Private assembly plan, not publication or final dependency qualification',
              binaries=list(selected.values()), sources=list(sources.values()),
              missing_original_identities=missing, qualification_gaps=gaps)
(notes / 'final-repository-plan.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(dict(binaries=len(selected), source_groups=len(sources), missing=missing, gaps=gaps), indent=2))
if not args.stage:
    raise SystemExit(0)
if gaps:
    raise SystemExit('Qualification incomplete; no release staging directory created')

destination = base / 'final-repository-inputs'
assert not destination.is_symlink()
destination.mkdir(exist_ok=True)
assert not (destination / 'source').is_symlink()
(destination / 'source').mkdir(exist_ok=True)
for row in selected.values():
    source = Path(row['archive'])
    retain(source, destination / source.name, row['sha256'])
for row in sources.values():
    for item in row['files']:
        source = Path(item['path'])
        target = destination / 'source' / source.name
        retain(source, target, item['sha256'])
(destination / 'selection.json').write_text(json.dumps(report, indent=2) + '\n')
print('Staged immutable inputs at', destination)
