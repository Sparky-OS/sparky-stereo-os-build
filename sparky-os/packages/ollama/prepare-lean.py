#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Qualify the payload of Ollama's checksum-pinned upstream-release recipe.

Ollama's executables and libraries are supplied by upstream. Do not project the unused source tree
and claim that this distribution build compiled or optimized them.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
sys.path.insert(0, str(HERE.parents[1] / 'repo'))
from lean.debian_prepare import prepare
import reproducible


def main(root, version):
    root = root.resolve()
    rules = (root / 'debian/rules').read_text()
    if ('sha256sum --quiet --strict -c MANIFEST.sha256' not in rules
            or 'dh_installsystemduser --no-enable' not in rules):
        raise ValueError('Review the changed upstream-release build recipe')
    manifest = root / 'release/MANIFEST.sha256'
    excluded = root / 'release/EXCLUDED.tsv'
    if not manifest.is_file() or not excluded.is_file():
        raise ValueError('Expected the repacked release with its MANIFEST.sha256 and EXCLUDED.tsv')
    with manifest.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    # the lean entry is dated by this recipe, never by the clock (ORDER 421b)
    os.environ['SOURCE_DATE_EPOCH'] = str(reproducible.recipe_epoch([HERE]))
    os.environ['DEBFULLNAME'] = 'Daniel Ramos (Capitain Jack)'
    os.environ['DEBEMAIL'] = 'Capitain_Jack@yahoo.com'
    prepare(root, version, HERE.parents[1])
    changelog = root / 'debian/changelog'
    text = changelog.read_text()
    first, separator, previous = text.partition('\n -- ')
    heading = first.split('\n', 1)[0]
    changelog.write_text(heading + '\n\n  * Qualify the installed payload of the checksum-pinned upstream release;\n'
                        '    retain exact source and HR companions. No native compilation is claimed.\n'
                        + separator + previous)
    path = root / 'debian/rules'
    updated = path.read_text()
    native = ('execute_before_dh_auto_configure:\n'
              '\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)\n')
    if updated.count(native) != 1:
        raise ValueError('Review the changed shared preparation hook')
    updated = updated.replace(native,
        '# The upstream executables are not compiled by this recipe.\n'
        '# Qualification below covers the installed payload only.\n')
    path.write_text(updated)
    (root / 'debian/upstream-binary.json').write_text(json.dumps({
        'kind': 'checksum-pinned-upstream-release',
        'manifest': str(manifest.relative_to(root)),
        'manifest_sha256': digest,
        'excluded': str(excluded.relative_to(root)),
        'integrity_check': 'release/MANIFEST.sha256 in override_dh_auto_build; the bundles were checked against '
                           'release.tsv and the release sha256sum.txt by make-orig.sh (no upstream signature exists)',
        'native_compilation_performed': False,
        'lean_code_scope': 'qualified installed payload; no native compiler-input saving claimed',
    }, indent=2) + '\n')
    print('Ollama: checksum-pinned upstream executables; payload qualification only, no native source projection')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    main(args.source, args.version)
