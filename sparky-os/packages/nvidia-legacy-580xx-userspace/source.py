#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pack the carry recipe, manifests and licence, without proprietary vendor binaries."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
toolkit, output = map(Path, sys.argv[1:])
sys.path.insert(0, str(toolkit / 'repo'))
import reproducible

version = '580.196.07-1+sparky3+lc1'
stamp = reproducible.epoch([HERE])
name = 'nvidia-graphics-drivers'
upstream = '580.196.07'
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='carry-source-', dir=output) as temporary:
    work = Path(temporary)
    source = work / (name + '-' + upstream)
    source.mkdir()
    for filename in ['build.sh', 'carry.py', 'source.py', 'packages.tsv', 'excluded.tsv',
                     'changelog', 'README.sparky-stereo.in', 'NVIDIA-LICENSE', 'cuda-debian12-archive-keyring.asc']:
        shutil.copy2(HERE / filename, source / filename)
    origin = 'https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/'
    vendors = []
    binaries = {}
    for line in (source / 'packages.tsv').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        package, arch, filename, size, sha = line.split('\t')
        vendors.append(dict(package=package, architecture=arch, url=origin + filename, size=int(size), sha256=sha))
        binaries.setdefault(package, set()).add(arch)
    (source / 'vendor-files.json').write_text(json.dumps(vendors, indent=2, sort_keys=True) + '\n')
    (source / 'README.source').write_text(
        'This is the edition carry recipe, not NVIDIA proprietary driver source.\n'
        'No vendor binary is embedded. vendor-files.json names the exact HTTPS inputs and hashes.\n'
        'NVIDIA-LICENSE is the verbatim distribution licence shipped in the carried packages.\n'
        'Rebuild with dpkg-buildpackage -b -us -uc in a container with HTTPS access.\n'
        'The recipe verifies the vendor Release, index and each archive, then checks unchanged payloads.\n')
    reproducible.normalize(source, stamp)
    orig = output / f'{name}_{upstream}.orig.tar.xz'
    subprocess.run(['tar', '--sort=name', '--mtime=@' + str(stamp), '--owner=0', '--group=0', '--numeric-owner',
                    '-C', str(work), '-cJf', str(orig.resolve()), source.name], check=True,
                   env={**os.environ, 'XZ_OPT': '-T2 -3'})
    debian = source / 'debian'
    (debian / 'source').mkdir(parents=True)
    (debian / 'source/format').write_text('3.0 (quilt)\n')
    control = ('Source: ' + name + '\nSection: non-free/libs\nPriority: optional\n'
               'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\n'
               'Build-Depends: python3, dpkg-dev, curl, gpgv, binutils, libc6-dev, python3-yaml, gcc, nodejs, node-acorn, perl, xz-utils\n'
               'Standards-Version: 4.7.4\nRules-Requires-Root: no\nHomepage: https://sparkylinux.org\n\n')
    for package, arches in sorted(binaries.items()):
        control += (f'Package: {package}\nArchitecture: {" ".join(sorted(arches))}\n'
                    'Description: NVIDIA files carried by the edition recipe\n'
                    ' Licensed vendor payload preserved byte for byte; see README.source.\n\n')
    (debian / 'control').write_text(control)
    (debian / 'changelog').write_text((source / 'changelog').read_text().replace('@SOURCE@', name))
    shutil.copy2(source / 'NVIDIA-LICENSE', debian / 'copyright')
    kit = debian / 'sparky-lean-toolkit'
    shutil.copytree(toolkit / 'lean', kit / 'lean', ignore=shutil.ignore_patterns('__pycache__', 'tests'))
    (kit / 'repo').mkdir()
    for file in ['provenance.sh', 'reproducible.py']:
        shutil.copy2(toolkit / 'repo' / file, kit / 'repo' / file)
    (kit / 'packages/dpkg-stereo').mkdir(parents=True)
    shutil.copy2(toolkit / 'packages/dpkg-stereo/LICENSE', kit / 'packages/dpkg-stereo/LICENSE')
    (debian / 'rules').write_text('''#!/usr/bin/make -f
export SPARKY_CARRY_TOOLKIT = $(CURDIR)/debian/sparky-lean-toolkit
export SPARKY_CARRY_SOURCE_BUILD = 1
export SPARKY_SCRATCH = $(CURDIR)/debian/work
export SOURCE_DATE_EPOCH = ''' + str(stamp) + '''
build:
binary binary-arch binary-indep:
	mkdir -p debian/work
	bash ./build.sh ../carry-built
	cp ../carry-built/*.deb ..
	python3 -c 'import pathlib,subprocess; fs=sorted(pathlib.Path("..").glob("*_580.196.07-1+sparky3+lc1_*.deb")); pathlib.Path("debian/files").write_text("".join(p.name+" non-free/libs optional\\n" for p in fs))'
clean:
	python3 -c 'import pathlib,shutil; p=pathlib.Path("debian/work"); shutil.rmtree(p) if p.exists() else None'
.PHONY: build binary binary-arch binary-indep clean
''')
    (debian / 'rules').chmod(0o755)
    reproducible.normalize_tree(source, stamp)
    shutil.copy2(orig, work / orig.name)
    subprocess.run(['dpkg-source', '-b', str(source)], cwd=work, check=True,
                   env={**os.environ, 'SOURCE_DATE_EPOCH': str(stamp)})
    for path in work.iterdir():
        if path.suffix == '.dsc' or path.name.endswith('.debian.tar.xz'):
            shutil.copy2(path, output / path.name)
print(name, version, 'recipe-only source packaged; no vendor binary embedded')
