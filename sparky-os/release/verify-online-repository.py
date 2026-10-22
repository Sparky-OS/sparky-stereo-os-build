#!/usr/bin/env python3
"""Check an already-published tree against its qualified local signed copy.

Read-only network checks. HTTPS verifies metadata and selected small client
packages; authenticated SSH checks every pool archive at the served web root.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import urllib.parse
import urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

sys.path.insert(0, str(cfg.TREE / 'sparky-os'))
from lean.package import stanzas

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', type=Path)
args = parser.parse_args()
repo = args.repository.resolve()
base = cfg.path('SPARKY_MIGRATION_WORK')
out = base / ('online-verification-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
out.mkdir()
url = 'https://repo.sparkyos.org/'
http = []

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def check_http(relative):
    path = repo / relative
    expected = digest(path)
    request = urllib.request.Request(url + urllib.parse.quote(relative, safe='/+~.-_'),
                                     headers={'Cache-Control': 'no-cache'})
    with urllib.request.urlopen(request, timeout=120) as response:
        actual = hashlib.sha256()
        count = 0
        while block := response.read(1024 * 1024):
            actual.update(block)
            count += len(block)
    assert count == path.stat().st_size and actual.hexdigest() == expected, relative
    http.append(dict(path=relative, sha256=expected, size=count))
    (out / 'https.json').write_text(json.dumps(http, indent=2) + '\n')

key = repo / 'sparky-stereo-repo.asc'
keys = subprocess.check_output(['gpg', '--batch', '--with-colons', '--show-keys', str(key)], text=True)
fingerprints = [line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:')]
assert fingerprints[0] == '10DFD38DAD1E4808BC688E5A945E5D079A2A0B9C'
subprocess.run(['gpg', '--batch', '--dearmor', '--output', str(out / 'keyring.gpg'), str(key)], check=True)
with (out / 'signature.log').open('w') as log:
    subprocess.run(['gpgv', '--keyring', str(out / 'keyring.gpg'),
                    str(repo / 'dists/mashtabba/InRelease')], stdout=log, stderr=subprocess.STDOUT, check=True)
for relative in ['sparky-stereo-repo.asc', 'index.html', 'dists/mashtabba/InRelease',
                 'dists/mashtabba/Release', 'dists/mashtabba/Release.gpg']:
    check_http(relative)
release = next(stanzas((repo / 'dists/mashtabba/Release').read_text()))
assert release['origin'] == 'Sparky Stereo OS' and release['codename'] == 'mashtabba'
for row in release['sha256'].splitlines():
    if not row.strip():
        continue
    expected, size, relative = row.split()
    path = repo / 'dists/mashtabba' / relative
    assert path.is_relative_to(repo) and '..' not in path.parts
    assert digest(path) == expected and path.stat().st_size == int(size)
    check_http('dists/mashtabba/' + relative)
    check_http('dists/mashtabba/' + str(Path(relative).parent / 'by-hash/SHA256' / expected))

pool = [dict(path=str(path.relative_to(repo)), size=path.stat().st_size, sha256=digest(path))
        for path in sorted((repo / 'pool').rglob('*')) if path.is_file()]
remote = r'''from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);records=json.load(sys.stdin)
checked=0
for row in records:
 relative=Path(row['path'])
 assert not relative.is_absolute() and relative.parts[0]=='pool' and '..' not in relative.parts
 path=root/relative
 assert path.is_file() and not path.is_symlink() and path.stat().st_size==row['size'],str(relative)
 with path.open('rb') as stream:assert hashlib.file_digest(stream,'sha256').hexdigest()==row['sha256'],str(relative)
 checked+=1
actual={str(p.relative_to(root)) for p in (root/'pool').rglob('*') if p.is_file()}
assert actual=={r['path'] for r in records},'Unexpected/missing remote pool files'
print(json.dumps(dict(passed=True,files=checked)))
'''
command = ['ssh', '-oBatchMode=yes', '-oConnectTimeout=8', '-oIdentitiesOnly=yes',
           '-i', cfg.get('SPARKY_SYNC_SSH_KEY'), cfg.get('SPARKY_SYNC_HOST'),
           'python3 -c ' + shlex.quote(remote) + ' ' + shlex.quote(cfg.get('SPARKY_SYNC_PATH').rstrip('/'))]
result = subprocess.run(command, input=json.dumps(pool), text=True, capture_output=True, check=True)
proof = json.loads(result.stdout)
assert proof['passed'] and proof['files'] == len(pool)
(out / 'pool.json').write_text(json.dumps(dict(files=pool, remote=proof), indent=2) + '\n')
for package in ['dpkg-stereo', 'sparky-stereo-apt', 'sparky-stereo-skills']:
    matches = list(repo.glob('pool/**/' + package + '_*.deb'))
    assert len(matches) == 1, package
    check_http(str(matches[0].relative_to(repo)))
(out / 'status.json').write_text(json.dumps(dict(state='passed', https_files=len(http),
    pool_files=len(pool), inrelease_sha256=digest(repo / 'dists/mashtabba/InRelease'),
    scope='Public HTTPS metadata/client archives and every served pool archive over authenticated SSH'), indent=2) + '\n')
print(out, 'PASS', flush=True)
