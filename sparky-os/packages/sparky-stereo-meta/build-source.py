#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Keep resolved meta-package controls and the generator inputs in a source archive."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

trees, version, out = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]).resolve()
root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root))
from lean import package
with tempfile.TemporaryDirectory(dir=out, prefix='.meta-source-') as temp:
    work = Path(temp)
    source = work / f'sparky-stereo-meta-{version}'
    (source / 'debian/source').mkdir(parents=True)
    shutil.copytree(trees, source / 'trees')
    shutil.copytree(root / 'lists', source / 'generator-inputs/lists', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    kit = source / 'release-toolkit'
    (kit / 'lean').mkdir(parents=True)
    for p in (root / 'lean').glob('*.py'):
        shutil.copy2(p, kit / 'lean' / p.name)
    shutil.copy2(root / 'lean/JvmLexer.java', kit / 'lean/JvmLexer.java')
    shutil.copy2(root / 'lean/smoke.tsv', kit / 'lean/smoke.tsv')
    shutil.copy2(root / 'packages/dpkg-stereo/LICENSE', kit / 'LICENSE')
    shutil.copy2(Path(__file__).parent / 'build.sh', source / 'generator-inputs/build.sh')
    shutil.copy2(__file__, source / 'generator-inputs/build-source.py')
    (source / 'README').write_text('''This source package retains the selected controls resolved by lists/make-meta.py
against the edition package index and the build machine's APT catalogue. Rebuilding
uses trees/ so that later repository changes cannot silently change dependencies.
The complete list/generator snapshot is in generator-inputs/; regeneration belongs
in the distribution workspace with its current package index and catalogue.
The authored trees are copied before Lean Code processing. No runtime files are
recovered by extracting an already sealed binary package.
''')
    control = '''Source: sparky-stereo-meta
Section: metapackages
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Build-Depends: python3
Standards-Version: 4.7.4
Rules-Requires-Root: no
Homepage: https://sparkylinux.org
'''
    for tree in sorted(trees.iterdir()):
        fields = package.control(tree)
        control += f'\nPackage: {tree.name}\nArchitecture: all\nSection: {fields["section"]}\nPriority: {fields["priority"]}\nDescription: Sparky Stereo OS development task\n Resolved development task dependencies for the edition.\n'
    (source / 'debian/control').write_text(control)
    (source / 'debian/source/format').write_text('3.0 (native)\n')
    (source / 'debian/changelog').write_text(f'''sparky-stereo-meta ({version}) unstable; urgency=medium

  * Development task update: distribution maintainer skills belong to the
    OS developer role; retain independent ordinary developer task selection.
  * Apply Lean Code during package assembly and retain exact source inputs.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 19 Oct 2026 18:00:00 -0300
''')
    copyright_file = next(trees.glob('*/usr/share/doc/*/copyright'))
    shutil.copy2(copyright_file, source / 'debian/copyright')
    (source / 'build.py').write_text('''#!/usr/bin/env python3
from pathlib import Path
import os, shutil, subprocess, sys, tempfile
os.umask(0o022)
root = Path(__file__).resolve().parent
sys.path.insert(0, str(root / 'release-toolkit'))
from lean import release, package
from lean.standalone import normalize_modes
with tempfile.TemporaryDirectory(dir=root, prefix='.build-') as work:
    for tree in sorted((root / 'trees').iterdir()):
        staging = Path(work) / tree.name
        shutil.copytree(tree, staging)
        normalize_modes(staging)
        fields = package.control(staging)
        name, version, arch = package.identity(fields)
        release.build_tree(staging, root.parent)
        subprocess.run(['dpkg-distaddfile', f'{name}_{version}_{arch}.deb', fields['section'], fields['priority']], cwd=root, check=True)
''')
    rules = source / 'debian/rules'
    rules.write_text('''#!/usr/bin/make -f
binary binary-indep:
	python3 build.py
binary-arch build build-arch build-indep clean:
.PHONY: binary binary-arch binary-indep build build-arch build-indep clean
''')
    rules.chmod(0o755)
    subprocess.run(['dpkg-source', '-b', str(source)], cwd=work, check=True)
    for suffix in ('dsc', 'tar.xz'):
        shutil.copy2(work / f'sparky-stereo-meta_{version}.{suffix}', out)
