#!/usr/bin/env python3
"""Apply the identical edition packaging and qualified C++ projection to a prepared form."""
import argparse
import datetime
import email.utils
import json
import os
from pathlib import Path
import shutil
import subprocess

from lean import debian_prepare, source_tree

PRESERVE = [
    ('vendor/*', 'vendored native inputs and Cargo checksums, as the toolchain recipe preserves them'),
    ('library/*', 'standard-library native source/generator inputs and rust-src payload'),
    ('tests/*', 'test fixtures whose source positions and comments are data'),
    ('src/*', 'benchmark, tool and CI native inputs outside the compiler LLVM wrapper'),
    ('compiler/rustc_codegen_gcc/*', 'fixtures of the backend this package does not build'),
]


def overlay(source, output, recipe, toolkit, scripts, epoch):
    if output.exists():
        raise RuntimeError('overlay output already exists')
    shutil.copytree(source, output, symlinks=True)
    os.environ.update(LC_ALL='C', SOURCE_DATE_EPOCH=str(epoch),
                      SOURCE_DATE_RFC2822=email.utils.format_datetime(datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)),
                      DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com')
    version = '1.99.1+dfsg1-1~exp1+stereo3d1'
    subprocess.run(['python3', str(recipe / 'edit-packaging.py'), str(output), version, 'discover',
                    "the edition's rustc 1.98.1+dfsg1-1+stereo3d1+lc1", str(recipe)], check=True)
    debian_prepare.prepare(output, version + '+lc1', toolkit, preserve_sources=PRESERVE)
    shutil.copy2(scripts / 'package_wrapper.py', output / 'debian/sparky-builddeb.py')
    rules = output / 'debian/rules'
    old = '\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance $(CURDIR)/debian/sparky-lean-toolkit/provenance.sh'
    text = rules.read_text()
    if text.count(old) != 1:
        raise RuntimeError('expected one Lean package hook')
    rules.write_text(text.replace(old, '\tpython3 $(CURDIR)/debian/sparky-builddeb.py $(CURDIR)'))
    source_tree.project_tree(output)
    validate(output)


def validate(output):
    source_tree.project_tree(output)  # completed projections are verified, never rendered a second time
    report = json.loads((output / '.sparky-lc/source.json').read_text())
    native = {n: r for n, r in report['files'].items() if n.startswith('compiler/rustc_llvm/')}
    counts = {s: sum(r['status'] == s for r in native.values()) for s in ('projected', 'unchanged', 'left')}
    if len(native) != 8 or counts != {'projected': 5, 'unchanged': 1, 'left': 2}:
        raise RuntimeError(f'changed native-input census: {native}')
    if {Path(n).name for n, r in native.items() if r['status'] == 'left'} != {'PassWrapper.cpp', 'RustWrapper.cpp'}:
        raise RuntimeError('unexpected native consumer preservation')
    print('PASS: common edition overlay; eight native inputs, five projected, two doc consumers, one unchanged')


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'output', 'recipe', 'toolkit', 'scripts'):
        ap.add_argument(name, type=Path)
    ap.add_argument('epoch', type=int)
    a = ap.parse_args()
    overlay(a.source, a.output, a.recipe, a.toolkit, a.scripts, a.epoch)
