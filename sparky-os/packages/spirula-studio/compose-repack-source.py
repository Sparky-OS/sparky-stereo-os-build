#!/usr/bin/python3
# Copyright 2026 Daniel Campos Ramos, GPL-3.0-or-later.
"""Compose a packaging-only successor from its pinned corresponding source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--from', dest='predecessor', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--toolkit', type=Path, required=True)
args = parser.parse_args()
recipe = Path(__file__).resolve().parent
plan = json.loads((recipe / 'debian/repack-predecessor.json').read_text())
previous = args.predecessor.resolve()
out = args.out.resolve()
toolkit = args.toolkit.resolve()
sha = lambda p: hashlib.file_digest(p.open('rb'), 'sha256').hexdigest()
for key in ['source', 'build_record']:
    item = plan[key]
    if sha(previous / item['name']) != item['sha256']:
        raise SystemExit('Pinned predecessor differs: ' + item['name'])
out.mkdir(parents=True, exist_ok=True)
root = out / 'spirula-studio-2026.11.12'
if root.exists():
    raise SystemExit('Refusing an existing source tree: ' + str(root))
subprocess.run(['dpkg-source', '-x', str(previous / plan['source']['name']), str(root)], check=True)
if json.loads((root / 'debian/build-origin.json').read_text())['fork'] != plan['fork_commit']:
    raise SystemExit('Predecessor fork differs from the reuse plan')
for p in previous.glob('*.orig*.tar.xz'):
    shutil.copy2(p, out / p.name)
from source_components import fonts as pack_fonts
pack_fonts(root / 'fonts', root, out / 'spirula-studio_2026.11.12.orig-fonts.tar.xz')
saved = out / 'predecessor-authored-debian'
shutil.copytree(root / 'debian', saved)
shutil.rmtree(root / 'debian')
shutil.copytree(recipe / 'debian', root / 'debian', ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
for name in ['patches', 'build-origin.json', 'source/options']:
    source = saved / name
    target = root / 'debian' / name
    if source.is_dir():
        shutil.copytree(source, target)
    else:
        shutil.copy2(source, target)
env = dict(os.environ, PYTHONPATH=str(toolkit))
subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(root), plan['version'], '--toolkit', str(toolkit),
                '--preserve-plan', str(saved / 'sparky-lean-preserve.json')], env=env, check=True)
with (root / 'debian/sparky-lean-toolkit/lean/smoke.tsv').open('a') as stream:
    stream.write('spirula-studio\t/usr/lib/spirula-studio/vulkan/spirula\t--version\n'
                 'spirula-studio-cuda\t/usr/lib/spirula-studio/cuda/spirula\t--version\n')
print(root)
