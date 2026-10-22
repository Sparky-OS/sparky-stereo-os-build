#!/usr/bin/env python3
"""Simulate the workstation upgrade against a signed candidate, without changing it.

Copy the host package database, APT indexes, sources and preferences into scratch.
Use an isolated APT_CONFIG with no host hooks. This complements the clean-container
installation check; it cannot prove an actual upgrade or authorize removals.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

base = cfg.path('SPARKY_MIGRATION_WORK')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', type=Path, nargs='?')
parser.add_argument('--preliminary-index', type=Path,
                    help='Private unsigned resolver view; never final release qualification')
parser.add_argument('--snapshot', type=Path,
                    help='Read a captured machine root instead of this workstation')
args = parser.parse_args()
machine = args.snapshot.resolve() if args.snapshot else Path('/')
snapshot = json.loads((machine / 'snapshot.json').read_text()) if args.snapshot else None
assert bool(args.repository) != bool(args.preliminary_index)
preliminary = args.preliminary_index is not None
repo = (args.preliminary_index or args.repository).resolve()
if preliminary:
    assert repo.is_relative_to(base) and (repo / 'Packages').is_file() and (repo / 'Release').is_file()
    assert (repo.parent / 'selection.json').is_file()
else:
    assert (repo / 'dists/mashtabba/InRelease').is_file()
    assert (repo / 'sparky-stereo-repo.asc').is_file()
assert shutil.disk_usage(base).free >= 14 * 1024**3
out = base / (('a10' if snapshot else 'host') + '-upgrade-preflight-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S'))
out.mkdir()
etc, state, cache = (out / name for name in ['etc', 'state', 'cache'])
for path in [etc, state, cache, etc / 'empty-parts', cache / 'archives/partial']:
    path.mkdir(parents=True, exist_ok=True)
for name in ['sources.list.d', 'preferences.d']:
    shutil.copytree(machine / 'etc/apt' / name, etc / name)
for name in ['sources.list', 'preferences']:
    original = machine / 'etc/apt' / name
    if original.exists():
        shutil.copy2(original, etc / name)
    else:
        (etc / name).touch()
shutil.copy2(machine / 'var/lib/dpkg/status', state / 'status')
shutil.copy2(machine / 'var/lib/apt/extended_states', state / 'extended_states')
shutil.copytree(machine / 'var/lib/apt/lists', state / 'lists',
                ignore=shutil.ignore_patterns('lock', 'partial', 'auxfiles'))
(state / 'lists/partial').mkdir()
(etc / 'empty-main').touch()
inputs = dict(
    machine_snapshot=snapshot,
    host_status_sha256=hashlib.sha256((state / 'status').read_bytes()).hexdigest(),
    index_release_sha256=hashlib.sha256((repo / ('Release' if preliminary else 'dists/mashtabba/InRelease')).read_bytes()).hexdigest(),
    preliminary=preliminary,
    host_apt_files_sha256={str(p.relative_to(etc)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in etc.rglob('*') if p.is_file()},
    scope=('PRELIMINARY mixed old/candidate resolver view; not release qualification. ' if preliminary else '')
          + 'Copied host APT state; simulation only, no installation or host hooks')
(out / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')

# Replace only the old edition source in the copy. Keep third-party update roots
# and the workstation's local FDK and GPU pins. The candidate is signature-checked.
local = etc / 'sources.list.d/sparky-stereo-local.list'
old_uri = 'file:/var/local/sparky-stereo-repo' if snapshot else 'file:' + str(cfg.path('SPARKY_REPO_DIR'))
assert local.is_file() and old_uri in local.read_text()
local.unlink()
if snapshot:
    for path in [etc / 'sources.list', *(etc / 'sources.list.d').iterdir()]:
        if path.is_file():
            text = path.read_text()
            for prefix in ['/usr/share/keyrings/', '/etc/apt/trusted.gpg.d/']:
                text = text.replace(prefix, str(machine) + prefix)
            path.write_text(text)
if preliminary:
    for name in ['sparky-stereo', 'sparky-stereo-only-ours']:
        shutil.copy2(repo.parent / 'apt-generator' / name, etc / 'preferences.d' / name)
    (etc / 'sources.list.d/sparky-stereo.sources').write_text(
        'Types: deb\nURIs: file:' + str(repo) + '\nSuites: ./\nTrusted: yes\n')
else:
    apt_archives = list(repo.glob('pool/**/sparky-stereo-apt_*_all.deb'))
    assert len(apt_archives) == 1
    payload = out / 'apt-payload'
    subprocess.run(['dpkg-deb', '-x', str(apt_archives[0]), str(payload)], check=True)
    for pin in (payload / 'etc/apt/preferences.d').iterdir():
        shutil.copy2(pin, etc / 'preferences.d' / pin.name)
    (etc / 'sources.list.d/sparky-stereo.sources').write_text(
        'Types: deb deb-src\nURIs: file:' + str(repo) + '\nSuites: mashtabba\n'
        'Components: main\nSigned-By: ' + str(repo / 'sparky-stereo-repo.asc') + '\n')
if snapshot:
    architectures = snapshot['architectures']
    default = snapshot['default_release']
else:
    architectures = [subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip()]
    architectures += subprocess.check_output(['dpkg', '--print-foreign-architectures'], text=True).split()
    default = subprocess.check_output(['apt-config', 'shell', 'release', 'APT::Default-Release'], text=True)
match = re.fullmatch("release='([^']*)'\n?", default)
assert match or not default, 'Review the host default release before simulating'
default_line = f'APT::Default-Release "{match[1]}";' if match else ''
config = out / 'apt.conf'
config.write_text(f'''Dir::Etc "{etc}";
Dir::Etc::main "{etc / 'empty-main'}";
Dir::Etc::parts "{etc / 'empty-parts'}";
Dir::Etc::trusted "{machine / 'etc/apt/trusted.gpg'}";
Dir::Etc::trustedparts "{machine / 'etc/apt/trusted.gpg.d'}";
Dir::State "{state}";
Dir::State::status "{state / 'status'}";
Dir::State::lists "{state / 'lists'}";
Dir::Cache "{cache}";
Dir::Cache::pkgcache "";
Dir::Cache::srcpkgcache "";
Dir::Log "{out / 'logs'}";
{default_line}
APT::Architecture "{architectures[0]}";
APT::Architectures {{ {' '.join('"' + a + '";' for a in architectures)} }};
Acquire::Retries "1";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
''')
env = dict(os.environ, APT_CONFIG=str(config), DEBIAN_FRONTEND='noninteractive')
dump = subprocess.check_output(['apt-config', 'dump'], env=env, text=True)
(out / 'apt-config.txt').write_text(dump)
assert not re.search(r'(?:Pre|Post)-(?:Invoke|Install)', dump), 'Host hooks leaked into simulation'
assert str(state / 'status') in dump and str(etc / 'empty-parts') in dump

results = []
def run(name, command, timeout=1200):
    with (out / (name + '.log')).open('w') as stream:
        try:
            rc = subprocess.run(command, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    lines = (out / (name + '.log')).read_text().splitlines()
    result = dict(name=name, exit_code=rc, removals=[l for l in lines if l.startswith('Remv ')],
                  installations=[l for l in lines if l.startswith('Inst ')])
    results.append(result)
    (out / 'checks.json').write_text(json.dumps(results, indent=2) + '\n')
    print(name, 'exit', rc, 'installations', len(result['installations']),
          'removals', len(result['removals']), flush=True)
    assert rc == 0, name

run('update', ['apt-get', '-o', 'APT::Update::Error-Mode=any', 'update'])
run('policy', ['apt-cache', 'policy', 'dpkg-stereo', 'sparky-stereo-apt',
              'sparky-stereo-skills', 'sparky-stereo-browser', 'linux-image-sparky-stereo',
              'nvidia-kernel-open-dkms-stereo3d', 'ffmpeg', 'libavcodec63:i386'])
# This optional NVIDIA storage module is already installed on the workstation.
# Its build overlay must be configured in a separate transaction BEFORE kernel
# maintainer scripts run; a metapackage recommendation does not ensure that order.
needs_nvfs_compat = any(
    re.search(r'^Package: nvidia-fs-dkms$', stanza, re.M)
    and re.search(r'^Status: install ok installed$', stanza, re.M)
    and re.search(r'^Version: 2\.29\.4(?:-|$)', stanza, re.M)
    for stanza in (state / 'status').read_text().split('\n\n'))
(out / 'upgrade-order.json').write_text(json.dumps(dict(
    compatibility_first=needs_nvfs_compat,
    instruction='Install and verify sparky-stereo-dkms-compat before kernel upgrade' if needs_nvfs_compat else 'No nvidia-fs 2.29.4 compatibility prerequisite',
    simulation_only=True), indent=2) + '\n')
if needs_nvfs_compat:
    run('compatibility-first', ['apt-get', '-s', '--no-remove', 'install', 'sparky-stereo-dkms-compat'])
run('upgrade', ['apt-get', '-s', '-o', 'Dpkg::Use-Pty=0', 'dist-upgrade'])
run('edition-configuration', ['apt-get', '-s', '-o', 'Dpkg::Use-Pty=0', 'install',
                             'sparky-stereo-apt', 'sparky-stereo-skills',
                             'sparky-stereo-browser', 'dpkg-stereo'])
assert hashlib.sha256((machine / 'var/lib/dpkg/status').read_bytes()).hexdigest() == inputs['host_status_sha256'], \
    'Host package database changed during simulation; repeat against the new state'
(out / 'status.json').write_text(json.dumps(dict(state='simulated-needs-review',
    scope=inputs['scope'], removals=sum(len(r['removals']) for r in results)), indent=2) + '\n')
print(out)
