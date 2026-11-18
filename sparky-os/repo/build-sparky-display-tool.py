#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Build a pinned, source-verified Sparky display tool with its one edition change."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('recipe', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
recipe = args.recipe.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
spec = json.loads((recipe / 'upstream.json').read_text())
for filename, digest in spec['files'].items():
    if hashlib.sha256((recipe / 'upstream' / filename).read_bytes()).hexdigest() != digest:
        raise SystemExit(f'{filename}: upstream checksum mismatch')
with tempfile.TemporaryDirectory(prefix='sparky-display-', dir=output) as temporary:
    work = Path(temporary)
    with tarfile.open(recipe / 'upstream/source.tar.gz') as archive:
        archive.extractall(work / 'upstream', filter='data')
    source = next((work / 'upstream').iterdir())
    tree = work / 'tree'
    subprocess.run(['dpkg-deb', '-R', str(recipe / 'upstream' / spec['binary']), str(tree)], check=True)
    name = spec['name']
    for path in tree.rglob('*'):
        if not path.is_file() or 'DEBIAN' in path.parts:
            continue
        relative = path.relative_to(tree).as_posix()
        if relative == f'usr/bin/{name}':
            original = source / 'bin' / name
        elif relative.startswith(f'usr/share/sparky/{name}/'):
            original = source / 'lang' / path.name
        elif relative.startswith('usr/share/applications/') or relative.startswith('usr/share/menu/'):
            original = source / 'share' / path.name
        elif relative.startswith('usr/share/icons/'):
            original = source / 'icons' / path.name
        elif relative == f'usr/share/doc/{name}/copyright':
            original = source / 'copyright'
        else:
            raise SystemExit(f'{relative}: no pinned source mapping')
        if original.read_bytes() != path.read_bytes():
            raise SystemExit(f'{relative}: published payload differs from pinned source')
    script = tree / 'usr/bin' / name
    before = script.read_text()
    old = 'OSCODE="`cat /etc/lsb-release | grep CODENAME | cut -d= -f2`"'
    new = '''OSCODE="$(sed -n 's/^VERSION=.*(\\([^)]*\\)).*/\\1/p' /etc/os-release)"'''
    if before.splitlines().count(old) != 1:
        raise SystemExit('The pinned OSCODE reader changed')
    script.write_text(before.replace(old, new))
    control = tree / 'DEBIAN/control'
    text = control.read_text()
    text = '\n'.join('Version: ' + spec['version'] if line.startswith('Version: ') else line
                     for line in text.splitlines()) + '\n'
    control.write_text(text)
    # The payload sources stay byte-identical apart from OSCODE; Lean Code and provenance run in the normal pipeline.
    shutil.copy2(recipe / 'ATTRIBUTIONS.md', tree / 'usr/share/doc' / name / 'ATTRIBUTIONS.md')
    subprocess.run(['python3', '-m', 'lean.standalone', str(tree), str(output), '--authoring', str(recipe)], check=True)
