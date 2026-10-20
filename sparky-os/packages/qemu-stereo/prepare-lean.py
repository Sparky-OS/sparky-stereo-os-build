#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Integrate QEMU's explicit Debian make graph without replacing its builders."""
import argparse
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from lean.debian_prepare import add_build_dependencies, prepare


def main(root, version):
    root = root.resolve()
    path = root / 'debian/rules'
    original = path.read_text()
    if '\n.NOTPARALLEL:\n' not in original or '\tbash debian/lean' in original:
        raise ValueError('Review the changed QEMU build graph')
    updated = original
    for target in ('configure-arch', 'build-arch', 'install-arch', 'build-indep', 'install-indep'):
        pattern = r'^' + target + r': (.+)$'
        if len(re.findall(pattern, updated, re.M)) != 1:
            raise ValueError(f'Review QEMU target {target}')
        updated = re.sub(pattern, target + r': lean-source \1', updated, flags=re.M)
    old = '\tdh_builddeb $a\n'
    if updated.count(old) != 1 or updated.count('clean:\tdebian/control\n') != 1:
        raise ValueError('Review QEMU assembly and cleanup hooks')
    updated = updated.replace(old,
        '\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance $(CURDIR)/debian/sparky-lean-toolkit/provenance.sh\n')
    updated = updated.replace('clean:\tdebian/control\n',
        'clean:\tdebian/control\n'
        '\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree restore $(CURDIR)\n'
        '\trm -rf .sparky-lc\n')
    updated += ('\n.PHONY: lean-source\nlean-source:\n'
                '\tPYTHONPATH=$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.source_tree project $(CURDIR)\n')
    saved = root / 'debian/rules.before-lean'
    if saved.exists():
        raise ValueError('Source is already integrated')
    saved.write_text(original)
    path.write_text('#!/usr/bin/make -f\n%:\n\tdh $@\n')
    try:
        prepare(root, version, HERE.parents[1],
                build_dependencies=['libstereo-declare-dev (>= 1.3.0)'], preserve_sources=[
            ('roms/*', 'Cross-built firmware and its header generators need target-specific qualification'),
            ('tests/tcg/*', 'Target-specific compiler and assembly fixtures must remain exact test inputs'),
        ])
    except Exception:
        path.write_text(original)
        raise
    path.write_text(updated)
    # control.mk regenerates debian/control during clean. Retain the checker
    # dependencies in its actual input too, so later source rebuilds keep them.
    template = root / 'debian/control-in'
    text = template.read_text()
    if not re.search(r'^Build-Depends:', text, re.M):
        raise ValueError('Review QEMU control template')
    template.write_text(add_build_dependencies(text,
        ('gcc', 'node-acorn', 'nodejs', 'perl', 'python3', 'python3-yaml',
         'libstereo-declare-dev (>= 1.3.0)')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    main(args.source, args.version)
