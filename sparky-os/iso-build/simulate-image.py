#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/10/26
# Copyright 2026 under the GNU GPL3 License
# A resolver-only model of rootfs.sh's ordered apt installs. The temporary dpkg status
# carries each resolved transaction into the next one; no maintainer scripts run.
import argparse
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile

import apt_pkg


def paragraphs(text):
    return [apt_pkg.TagSection(p + '\n') for p in text.split('\n\n') if p.strip()]


def identity(record):
    return record['Package'], record['Architecture']


def recipe_installs(recipe, base):
    installs = []
    for line in recipe.replace('\\\n', ' ').splitlines():
        line = line.strip()
        if not line.startswith('apt_in install '):
            continue
        words = shlex.split(line.replace('$(cat /tmp/base)', '__BASE__'), comments=True)[2:]
        if any('$' in word or '`' in word for word in words):
            raise ValueError('unsupported shell expansion in recipe: ' + line)
        installs.append([item for word in words for item in (base if word == '__BASE__' else [word])])
    if not installs:
        raise ValueError('recipe contains no apt installs')
    return installs


def version_record(cache, records, name, version):
    package = cache[name]
    for candidate in package.version_list:
        if candidate.ver_str == version:
            records.lookup(candidate.file_list[0])
            return apt_pkg.TagSection(records.record)
    raise ValueError(f'missing exact metadata: {name}={version}')


def apply_preferences(record, out):
    # This package's conffile takes effect before the NVIDIA install in rootfs.sh.
    # Extract only that conffile, never run package scripts or alter the probe host.
    with tempfile.TemporaryDirectory(dir=out) as download:
        subprocess.run(['apt-get', 'download', record['Package'] + '=' + record['Version']],
                       cwd=download, check=True)
        deb, = Path(download).glob('*.deb')
        archive = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(deb)], stdout=subprocess.PIPE)
        count = 0
        with tarfile.open(fileobj=archive.stdout, mode='r|') as payload:
            for member in payload:
                name = member.name.removeprefix('./')
                if member.isfile() and name.startswith('etc/apt/preferences.d/'):
                    (out / 'preferences.d' / Path(name).name).write_bytes(payload.extractfile(member).read())
                    count += 1
        if archive.wait() or not count:
            raise ValueError('NVIDIA driver lock has no readable preferences')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--recipe', type=Path, required=True)
    parser.add_argument('--status', type=Path, required=True)
    parser.add_argument('--allow-remove', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    apt_pkg.init()
    args.out.mkdir(parents=True, exist_ok=False)
    out = args.out.resolve()
    shutil.copytree('/etc/apt/preferences.d', out / 'preferences.d')
    (out / 'preferences.d' / 'beta-build-no-debian-kernel').write_text(
        'Package: /^linux-(image|headers|binary|modules|signed|base)-.*amd64(-unsigned)?$/\n'
        'Pin: release o=Debian\nPin-Priority: -1\n')
    (out / 'preferences.d' / 'beta-build-no-zfs').write_text(
        'Package: zfs-dkms zfsutils-linux zfs-zed\nPin: release *\nPin-Priority: -1\n')
    installed = {identity(p): str(p) for p in paragraphs(args.status.read_text())
                 if p.get('Status') == 'install ok installed'}
    initial = dict(installed)
    allowed_removals = {line.strip() for line in args.allow_remove.read_text().splitlines()
                        if line.strip() and not line.startswith('#')} if args.allow_remove else set()
    removals = []
    cache = apt_pkg.Cache()
    records = apt_pkg.PackageRecords(cache)
    stages = recipe_installs(args.recipe.read_text(), args.base.read_text().split())
    (out / 'requests.json').write_text(json.dumps(stages, indent=2) + '\n')
    options = ['-o', 'Dir::State::status=' + str(out / 'status'),
               '-o', 'Dir::State::extended_states=' + str(out / 'extended_states'),
               '-o', 'Dir::Etc::preferencesparts=' + str(out / 'preferences.d'),
               '-o', 'Dir::Cache::pkgcache=', '-o', 'Dir::Cache::srcpkgcache=']
    for number, targets in enumerate(stages, 1):
        (out / 'status').write_text('\n\n'.join(installed.values()) + '\n\n')
        log = out / f'{number:02d}.log'
        print(f'== rootfs install {number}/{len(stages)}; log: {log}', flush=True)
        with log.open('w') as output:
            result = subprocess.run(['apt-get', '-s', '-o', 'Debug::NoLocking=1',
                                     *options, 'install', *targets], stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f'resolver failed ({result.returncode}); see {log}; no size result')
        transaction = log.read_text()
        changes = re.findall(r'^Inst (\S+) (?:\[\S+\] )?\((\S+) ', transaction, re.M)
        if len(changes) != len(re.findall(r'^Inst ', transaction, re.M)):
            raise ValueError(f'unparsed installation in {log}')
        selected = [version_record(cache, records, name, version) for name, version in changes]
        for name in re.findall(r'^Remv (\S+)', transaction, re.M):
            package = name.split(':')[0]
            reason = 'base-remove.list' if package in allowed_removals else None
            # CUDA's kernel-support explicitly replaces its transitional nvidia-detect.
            # Record declared same-name replacements separately from simple removals.
            for record in selected:
                provides = {n for group in apt_pkg.parse_depends(record.get('Provides', '')) for n, _, _ in group}
                conflicts = {n for group in apt_pkg.parse_depends(record.get('Conflicts', '')) for n, _, _ in group}
                if package in provides & conflicts:
                    reason = 'provided replacement: ' + record['Package']
                    break
            if reason is None:
                raise ValueError(f'unexpected removal of {name} in {log}')
            for key in list(installed):
                if key[0] == name or ':'.join(key) == name:
                    removed = apt_pkg.TagSection(installed.pop(key))
                    removals.append({'stage': number, 'package': name, 'version': removed['Version'],
                                     'installed_kib': int(removed['Installed-Size']), 'reason': reason})
        for record in selected:
            installed[identity(record)] = str(record).rstrip() + '\nStatus: install ok installed\n'
            if record['Package'] == 'sparky-stereo-nvidia-driver-lock':
                apply_preferences(record, out)
    (out / 'status').write_text('\n\n'.join(installed.values()) + '\n\n')
    final = {key: apt_pkg.TagSection(value) for key, value in installed.items()}
    if any(re.fullmatch(r'linux-(?:image|headers)-.*amd64(?:-unsigned)?', p['Package'])
           for p in final.values()):
        raise ValueError('Debian kernel/headers in resolved image')
    rows = ['package\tarchitecture\tversion\tinstalled_kib\tarchive_bytes\tsource\tsha256\tchange']
    for key, record in sorted(final.items()):
        if 'Installed-Size' not in record:
            raise ValueError('missing Installed-Size for ' + record['Package'])
        before = apt_pkg.TagSection(initial[key]) if key in initial else None
        change = 'added' if before is None else ('unchanged' if before['Version'] == record['Version'] else 'changed')
        rows.append('\t'.join([*key, record['Version'], record['Installed-Size'], record.get('Size', ''),
                               record.get('Source', record['Package']), record.get('SHA256', ''), change]))
    (out / 'closure.tsv').write_text('\n'.join(rows) + '\n')
    (out / 'removals.json').write_text(json.dumps(removals, indent=2) + '\n')
    summary = {'packages': len(final), 'installed_kib': sum(int(p['Installed-Size']) for p in final.values()),
               'removed': sorted(':'.join(key) for key in initial.keys() - final.keys()),
               'method': 'ordered apt simulation with temporary dpkg status; metadata sizes, not disk usage or compressed ISO size'}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
