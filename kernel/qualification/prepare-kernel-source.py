#!/usr/bin/env python3
"""Export the audited build-8 feature set into a retained build-9 source package."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'config'))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sparky-os' / 'release'))
import local_config as cfg

base = cfg.path('SPARKY_MIGRATION_WORK')
flavour = sys.argv[1]
kit = (cfg.TREE / 'kernel')
manifest_path = base / 'kernel-inputs/accepted-source-manifests.json'
subprocess.run([sys.executable, str(kit / 'lean/check-flavours.py'), str(manifest_path)], check=True)
manifest = json.loads(manifest_path.read_text())[flavour]
repo = (cfg.path('SPARKY_INPUTS_DIR') / 'kernel-soul/work/kt')
series = (cfg.path('SPARKY_INPUTS_DIR') / 'kernel-soul/work/series')
if shutil.disk_usage(base).free < 26 * 1024**3:
    raise SystemExit('Kernel source preparation waits for 26 GiB root free')
for row in manifest['patches']:
    assert hashlib.sha256((series / row['path']).read_bytes()).hexdigest() == row['sha256']
work = base / 'kernel-sources' / flavour
work.mkdir(parents=True)
source = work / 'source'
source.mkdir()
export = subprocess.Popen(['git', '-C', str(repo), 'archive', manifest['source_tree']], stdout=subprocess.PIPE)
unpack = subprocess.run(['tar', '-xf', '-', '-C', str(source)], stdin=export.stdout)
export.stdout.close()
assert unpack.returncode == 0 and export.wait() == 0
manifest['packaging_commit'] = subprocess.check_output(['git', '-C', str(kit.parent), 'rev-parse', 'HEAD'], text=True).strip()
manifest['packaging_status'] = 'Kernel Lean Code recipe under qualification; exact recipe retained in debian/'
manifest['version'] = '7.3.0~rc6-9+lc1'
manifest['configuration_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (kit / 'config').iterdir() if p.is_file()}
(source / 'SOURCE.edition.json').write_text(json.dumps(manifest, indent=2) + '\n')
subprocess.run(['python3', str(kit / 'lean/prepare.py'), str(source), str(kit), '--counter', '9'], check=True)
archive = work / f'linux-stereo-{flavour}_7.3.0~rc6.orig.tar.xz'
with archive.open('wb') as sink:
    packed = subprocess.Popen(['tar', '-C', str(source), '--exclude=./debian',
                               '--transform=flags=r;s,^\\.,linux-stereo-' + flavour + '-7.3.0~rc6,',
                               '-cf', '-', '.'], stdout=subprocess.PIPE)
    compressed = subprocess.Popen(['xz', '-T2', '-3'], stdin=packed.stdout, stdout=sink)
    packed.stdout.close()
    assert compressed.wait() == 0 and packed.wait() == 0
subprocess.run(['dpkg-source', '-b', str(source)], cwd=work, check=True)
print(flavour, 'retained source prepared; not a compiled or release-qualified kernel')
