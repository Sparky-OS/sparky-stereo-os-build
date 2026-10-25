#!/usr/bin/env python3
"""Export an accepted, patched feature set into a retained Lean Code kernel source package.

    prepare-kernel-source.py FLAVOUR [--counter N] [--source-dir DIR] [--manifest FILE] [--packaging-revision R]

Without --source-dir the tree named by the manifest is exported from the kernel-soul repository (build 9).
With it, DIR is the already patched export (tag plus the manifest's patches, no .git) and is copied as it is.
"""
import argparse
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lean'))
import upstream

parser = argparse.ArgumentParser()
parser.add_argument('flavour', choices=['base', 'v3', 'rt'])
parser.add_argument('--counter', default='9')
parser.add_argument('--source-dir', type=Path)
parser.add_argument('--manifest', type=Path)
parser.add_argument('--packaging-revision')
args = parser.parse_args()
base = cfg.path('SPARKY_MIGRATION_WORK')
flavour = args.flavour
kit = (cfg.TREE / 'kernel')
manifest_path = args.manifest or base / 'kernel-inputs/accepted-source-manifests.json'
subprocess.run([sys.executable, str(kit / 'lean/check-flavours.py'), str(manifest_path)], check=True)
manifest = json.loads(manifest_path.read_text())[flavour]
upstream_version = upstream.versions(manifest['tag'])[1]
version = upstream_version + '-' + args.counter + ('.' + args.packaging_revision if args.packaging_revision else '') + '+lc1'
repo = (cfg.path('SPARKY_INPUTS_DIR') / 'kernel-soul/work/kt')
series = cfg.TREE / 'kernel/series'
if shutil.disk_usage(base).free < 26 * 1024**3:
    raise SystemExit('Kernel source preparation waits for 26 GiB root free')
for row in manifest['patches']:
    assert hashlib.sha256((series / row['path']).read_bytes()).hexdigest() == row['sha256']
work = base / 'kernel-sources' / flavour
work.mkdir(parents=True)
source = work / 'source'
source.mkdir()
if args.source_dir:
    shutil.copytree(args.source_dir, source, symlinks=True, dirs_exist_ok=True)
    shutil.rmtree(source / '.git', ignore_errors=True)
else:
    export = subprocess.Popen(['git', '-C', str(repo), 'archive', manifest['source_tree']], stdout=subprocess.PIPE)
    unpack = subprocess.run(['tar', '-xf', '-', '-C', str(source)], stdin=export.stdout)
    export.stdout.close()
    assert unpack.returncode == 0 and export.wait() == 0
manifest['packaging_commit'] = subprocess.check_output(['git', '-C', str(kit.parent), 'rev-parse', 'HEAD'], text=True).strip()
manifest['packaging_status'] = 'Kernel Lean Code recipe under qualification; exact recipe retained in debian/'
manifest['version'] = version
manifest['configuration_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (kit / 'config').iterdir() if p.is_file()}
(source / 'SOURCE.edition.json').write_text(json.dumps(manifest, indent=2) + '\n')
subprocess.run(['python3', str(kit / 'lean/prepare.py'), str(source), str(kit), '--counter', args.counter]
               + (['--packaging-revision', args.packaging_revision] if args.packaging_revision else []), check=True)
archive = work / f'linux-stereo-{flavour}_{upstream_version}.orig.tar.xz'
with archive.open('wb') as sink:
    packed = subprocess.Popen(['tar', '-C', str(source), '--exclude=./debian',
                               '--transform=flags=r;s,^\\.,linux-stereo-' + flavour + '-' + upstream_version + ',',
                               '-cf', '-', '.'], stdout=subprocess.PIPE)
    compressed = subprocess.Popen(['xz', '-T2', '-3'], stdin=packed.stdout, stdout=sink)
    packed.stdout.close()
    assert compressed.wait() == 0 and packed.wait() == 0
subprocess.run(['dpkg-source', '-b', str(source)], cwd=work, check=True)
print(flavour, 'retained source prepared; not a compiled or release-qualified kernel')
