#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Qualify the payload of Vibe's existing signed-upstream-release recipe.

Vibe's executable is supplied by upstream. Do not project its unused source tree
and claim that this distribution build compiled or optimized that executable.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from lean.debian_prepare import prepare


def main(root, version):
    root = root.resolve()
    rules = (root / 'debian/rules').read_text()
    if ('minisign -V -p release/vibe.pub -x release/vibe.sig' not in rules
            or 'dpkg-deb -x release/vibe_' not in rules):
        raise ValueError('Review the changed upstream-release build recipe')
    files = list((root / 'release').glob('vibe_*_amd64.deb'))
    if len(files) != 1:
        raise ValueError('Expected exactly one retained upstream release archive')
    archive = files[0]
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    os.environ['DEBFULLNAME'] = 'Daniel Ramos (Capitain Jack)'
    os.environ['DEBEMAIL'] = 'Capitain_Jack@yahoo.com'
    prepare(root, version, HERE.parents[1])
    changelog = root / 'debian/changelog'
    text = changelog.read_text()
    first, separator, previous = text.partition('\n -- ')
    heading = first.split('\n', 1)[0]
    changelog.write_text(heading + '\n\n  * Qualify the installed payload of the signed upstream release; retain\n'
                        '    exact source and HR companions. No native compilation is claimed.\n'
                        + separator + previous)
    path = root / 'debian/rules'
    updated = path.read_text()
    native = ('execute_before_dh_auto_configure:\n'
              '\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)\n')
    if updated.count(native) != 1:
        raise ValueError('Review the changed shared preparation hook')
    updated = updated.replace(native,
        '# The signed upstream executable is not compiled by this recipe.\n'
        '# Qualification below covers the installed payload only.\n')
    # Preserve the authenticated executables byte for byte. Re-stripping a
    # release binary would invalidate that proof without a source compilation.
    updated += '\noverride_dh_strip:\noverride_dh_dwz:\n'
    path.write_text(updated)
    (root / 'debian/upstream-binary.json').write_text(json.dumps({
        'kind': 'signed-upstream-release',
        'archive': str(archive.relative_to(root)),
        'sha256': digest,
        'signature': 'release/vibe.sig',
        'public_key': 'release/vibe.pub',
        'signature_check': 'minisign -V in override_dh_auto_build',
        'native_compilation_performed': False,
        'lean_code_scope': 'qualified installed payload; no native compiler-input saving claimed',
    }, indent=2) + '\n')
    print('Vibe: signed upstream executable; payload qualification only, no native source projection')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    main(args.source, args.version)
