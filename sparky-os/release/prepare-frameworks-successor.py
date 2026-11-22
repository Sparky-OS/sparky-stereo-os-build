#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
"""Carry an audited edition Frameworks source onto a pinned Debian successor.

The manifest belongs to the source's existing recipe. Both descriptors and all
components are verified before extraction; no patch is implicitly dropped.
Run inside the package build container, then use lean.debian_prepare and the
normal dpkg-buildpackage source-and-binary build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('manifest', type=Path)
parser.add_argument('debian_inputs', type=Path)
parser.add_argument('published_inputs', type=Path)
parser.add_argument('work', type=Path)
args = parser.parse_args()
recipe = args.manifest.resolve().parent
manifest = json.loads(args.manifest.read_text())
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
source = work / 'source'
if source.exists():
    parser.error('source already exists; use a fresh work directory')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def descriptor(directory, kind):
    path = directory / manifest[kind + '_descriptor']
    assert sha(path) == manifest[kind + '_descriptor_sha256'], path
    text = path.read_text()
    match = re.search(r'^Checksums-Sha256:\n((?:[ \t].*\n)+)', text, re.M)
    assert match, path
    files = []
    for line in match[1].splitlines():
        checksum, size, name = line.split()
        assert Path(name).name == name
        component = directory / name
        assert component.stat().st_size == int(size) and sha(component) == checksum, component
        files.append(component)
    return path, files


debian_dsc, debian_files = descriptor(args.debian_inputs.resolve(), 'debian')
old_dsc, old_files = descriptor(args.published_inputs.resolve(), 'published')
for path in debian_files:
    if '.orig.tar.' in path.name:
        shutil.copyfile(path, work / path.name)
subprocess.run(['dpkg-source', '--skip-patches', '-x', str(debian_dsc), str(source)], check=True)
published = work / 'published-packaging'
with tarfile.open(next(p for p in old_files if '.debian.tar.' in p.name)) as archive:
    archive.extractall(published, filter='data')
subprocess.run(['patch', '--batch', '--fuzz=0', '-p1', '-i', str(recipe / manifest['packaging_patch'])], cwd=source, check=True)
patchdir = source / 'debian/patches'
patchdir.mkdir(exist_ok=True)
series = patchdir / 'series'
names = [s.strip() for s in series.read_text().splitlines()] if series.exists() else []
oldnames = [s.strip() for s in (published / 'debian/patches/series').read_text().splitlines() if s.strip() and not s.startswith('#')]
assert oldnames == [p['name'] for p in manifest['patches']], 'published series changed'
for patch in manifest['patches']:
    old = published / 'debian/patches' / patch['name']
    assert sha(old) == patch['published_sha256'], old
    if patch['fate'] == 'Debian retained':
        assert patch['name'] in names and (patchdir / patch['name']).exists()
        continue
    assert patch['name'] not in names
    carried = recipe / patch['replacement'] if 'replacement' in patch else old
    if 'replacement' in patch:
        assert sha(carried) == patch['replacement_sha256'], carried
    shutil.copyfile(carried, patchdir / patch['name'])
    names.append(patch['name'])
for catalogue in manifest.get('additional_catalogues', []):
    path = Path(__file__).resolve().parents[1] / catalogue['path']
    assert sha(path) == catalogue['sha256'], path
    assert path.name not in names
    shutil.copyfile(path, patchdir / path.name)
    names.append(path.name)
series.write_text('\n'.join(names) + '\n')
for relative in manifest['carry_debian_paths']:
    before = published / relative
    after = source / relative
    assert not after.exists(), after
    after.parent.mkdir(parents=True, exist_ok=True)
    if before.is_dir():
        shutil.copytree(before, after)
    else:
        shutil.copyfile(before, after)
# Binary test fixtures carried by the Debian tarball are source inputs too.
for before in published.rglob('*'):
    relative = before.relative_to(published)
    if not before.is_file() or relative.parts[0] == 'debian':
        continue
    after = source / relative
    assert not after.exists() or after.read_bytes() == before.read_bytes(), after
    after.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(before, after)
newlog = (source / 'debian/changelog').read_text()
oldlog = (published / 'debian/changelog').read_text()
base = re.search(r'^' + re.escape(manifest['source']) + r' \(6\.30\.0-1\) ', newlog, re.M)
assert base, 'Debian changelog lost the published upstream base'
recipe_toolkit = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(recipe_toolkit / 'repo'))
import reproducible
stamp = reproducible.rfc2822(int(os.environ['SOURCE_DATE_EPOCH']))
entry = (f"{manifest['source']} ({manifest['version']}) unstable; urgency=medium\n\n"
         "  * Follow Debian Frameworks 6.32 while retaining every edition patch,\n"
         "    source fixture, translation and changelog entry. Rebase overlapping\n"
         "    context without changing stereo behavior or upstream fixes.\n\n"
         f" -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {stamp}\n\n")
(source / 'debian/changelog').write_text(entry + newlog[:base.start()] + oldlog)
subprocess.run(['dpkg-source', '--before-build', str(source)], check=True)
reproducible.normalize_tree(source, int(os.environ['SOURCE_DATE_EPOCH']))
print(source)
