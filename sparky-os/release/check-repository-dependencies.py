#!/usr/bin/env python3
"""Early resolver check; unbuilt packages remain explicitly labelled old inputs.

This is NOT a release index. It is private, unsigned and mounted only in an
isolated container. Final release qualification must rerun with no old inputs.
"""
from datetime import datetime, timezone
from email.utils import formatdate
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
repo = cfg.path('SPARKY_REPO_DIR')
kit = (cfg.TREE / 'sparky-os')
sys.path.insert(0, str(kit))
from lean.package import stanzas

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only', action='append', default=[],
                    help='Repeat selected role or Wine/Mesa Multi-Arch checks after a repair')
parser.add_argument('--prepare-only', action='store_true',
                    help='Create the private index for a copied-machine simulation without running role checks')
args = parser.parse_args()
assert not (args.prepare_only and args.only), 'Choose index preparation or selected role checks'

out = base / ('dependency-preflight-' + datetime.now(timezone.utc).strftime('%H%M%S'))
out.mkdir()
index = out / 'index'
index.mkdir()
progress = json.loads((notes / 'migration-progress.json').read_text())
initial = json.loads((notes / 'current-packages.json').read_text())
chosen = {(r['Package'], r['Architecture']): (repo / r['Filename'], 'existing') for r in initial}
for row in progress['archives']:
    path = Path(row['archive'])
    key = row['Package'], row['Architecture']
    if key in chosen:
        version = subprocess.check_output(['dpkg-deb', '-f', str(chosen[key][0]), 'Version'], text=True).strip()
        if subprocess.run(['dpkg', '--compare-versions', row['Version'], 'lt', version]).returncode == 0:
            continue
    chosen[key] = (path, 'candidate')
for replacement in json.loads((notes / 'package-replacements.json').read_text()):
    key = replacement['replacement'], replacement['architecture']
    if key in chosen and chosen[key][1] == 'candidate':
        version = subprocess.check_output(['dpkg-deb', '-f', str(chosen[key][0]), 'Version'], text=True).strip()
        if version == replacement['replacement_version']:
            chosen.pop((replacement['original'], replacement['architecture']), None)
records = []
with (index / 'Packages').open('w') as stream:
    for key, (path, state) in sorted(chosen.items()):
        control = subprocess.check_output(['dpkg-deb', '-f', str(path)], text=True).rstrip()
        fields = next(stanzas(control))
        with path.open('rb') as archive:
            digest = hashlib.file_digest(archive, 'sha256').hexdigest()
        # No .debs are copied here: this view is for apt --simulate only.
        stream.write(control + f'\nFilename: ./pool/{path.name}\nSize: {path.stat().st_size}\nSHA256: {digest}\n\n')
        records.append(dict(package=key[0], architecture=key[1], version=fields['version'],
                            state=state, archive=str(path), sha256=digest,
                            lean=fields.get('sparky-lean-code', '').startswith('lc1 ')))
(out / 'selection.json').write_text(json.dumps(records, indent=2) + '\n')
data = (index / 'Packages').read_bytes()
(index / 'Release').write_text(
    'Origin: Sparky Stereo OS\nLabel: Private dependency rehearsal\nSuite: testing\n'
    'Codename: mashtabba\nArchitectures: amd64 i386 all\nDate: ' + formatdate(usegmt=True) +
    '\nSHA256:\n ' + hashlib.sha256(data).hexdigest() + f' {len(data)} Packages\n')
generator = out / 'apt-generator'
shutil.copytree(kit / 'apt', generator)
subprocess.run(['python3', str(generator / 'make-only-ours.py'), str(index)], check=True)
roles = sorted({r['package'] for r in records if r['package'].startswith('task-sparky-') or r['package'] == 'sparky-stereo'})
(out / 'roles.json').write_text(json.dumps(roles) + '\n')
assert set(args.only) <= set(roles) | {'wine-multiarch', 'mesa-multiarch'}, 'Unknown check name'
(out / 'only.json').write_text(json.dumps(args.only) + '\n')
if args.prepare_only:
    (out / 'status.json').write_text(json.dumps(dict(
        state='index-only', passed=False,
        scope='Private preliminary resolver input; no dependency checks run',
        total=len(records), unmarked=sum(not r['lean'] for r in records),
        retained_old=sum(r['state'] == 'existing' for r in records)), indent=2) + '\n')
    print(out, flush=True)
    raise SystemExit(0)
inner = r'''from pathlib import Path
import json,subprocess
out=Path('/proof');results=[]
checks=[(role,[role]) for role in json.loads((out/'roles.json').read_text())]
checks.append(('wine-multiarch',['wine64','wine32:i386','libwine:amd64','libwine:i386']))
checks.append(('mesa-multiarch',['libgl1-mesa-dri:amd64','libgl1-mesa-dri:i386','mesa-vulkan-drivers:amd64','mesa-vulkan-drivers:i386']))
only=json.loads((out/'only.json').read_text())
if only:checks=[case for case in checks if case[0] in only]
for name,packages in checks:
 with (out/(name+'.log')).open('w') as f:
  try:
   rc=subprocess.run(['apt-get','-s','-o','Dpkg::Use-Pty=0','install',*packages],stdout=f,stderr=subprocess.STDOUT,timeout=600).returncode
  except subprocess.TimeoutExpired:
   rc=124
 text=(out/(name+'.log')).read_text();removed=[l for l in text.splitlines() if l.startswith('Remv ')]
 results.append(dict(name=name,exit_code=rc,removed=removed,passed=rc==0 and not removed))
 (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(name,'PASS' if results[-1]['passed'] else 'FAIL',flush=True)
(out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
raise SystemExit(not all(r['passed'] for r in results))
'''
(out / 'inner.py').write_text(inner)
recipe = '''set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
rm -f /etc/apt/sources.list.d/debian.sources
printf 'deb https://deb.debian.org/debian testing main contrib non-free non-free-firmware\n' > /etc/apt/sources.list
printf 'deb [trusted=yes] file:/proof/index ./\n' > /etc/apt/sources.list.d/candidates.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
cp /host-sparky.sources /etc/apt/sources.list.d/sparky.sources
cp /proof/apt-generator/sparky-stereo /etc/apt/preferences.d/edition
cp /proof/apt-generator/sparky-stereo-only-ours /etc/apt/preferences.d/edition-only
apt-get update
python3 /proof/inner.py
'''
(out / 'run.sh').write_text(recipe)
command = ['docker', 'run', '--rm', '--name', 'sparky-lc-dependency-preflight', '--cpus', '2', '--memory', '4g',
           '-v', str(out) + ':/proof',
           '-v', '/etc/apt/sources.list.d/sparky.sources:/host-sparky.sources:ro',
           '-v', '/etc/apt/trusted.gpg.d/sparky-repo.asc:/etc/apt/trusted.gpg.d/sparky-repo.asc:ro',
           '-v', '/usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro',
           'sparky-lc-migration:20261020', 'bash', '/proof/run.sh']
with (out / 'driver.log').open('w') as log:
    process = start_build(command, 'sparky-lc-dependency-preflight', log)
    rc = process.wait()
status = dict(passed=rc == 0, exit_code=rc, scope='Early isolated resolver rehearsal, not release qualification',
              total=len(records), unmarked=sum(not r['lean'] for r in records),
              retained_old=sum(r['state'] == 'existing' for r in records))
(out / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
print(out, status, flush=True)
raise SystemExit(rc)
