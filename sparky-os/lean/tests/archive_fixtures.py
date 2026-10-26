"""An offline signed archive, with explicit compiler-runtime files as test inputs.

The synthetic key signs only this disposable fixture repository. It is unrelated
to distribution keys. The fixture archive is regenerated from the same controls
and dependency choices, and requires no network or host package database.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def deb(base, name, version='1', arch='amd64', depends='', extra='', files=None):
    stage = base / f'{name}-{version.replace(":", "_")}-{arch}'
    (stage / 'DEBIAN').mkdir(parents=True)
    (stage / 'DEBIAN/control').write_text(
        f'Package: {name}\nVersion: {version}\nArchitecture: {arch}\n'
        'Maintainer: Fixture <fixture@example.invalid>\nDescription: Archive fixture\n' +
        (f'Depends: {depends}\n' if depends else '') + extra)
    for name, content in (files or {}).items():
        path = stage / name.lstrip('/')
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, Path):
            shutil.copyfile(content, path)
            path.chmod(0o755)
        elif isinstance(content, tuple):
            path.symlink_to(content[0])
        else:
            path.write_bytes(content)
    out = base / (stage.name + '.deb')
    subprocess.run(['dpkg-deb', '--build', '--root-owner-group', str(stage), str(out)],
                   check=True, stdout=subprocess.DEVNULL)
    return out


def signed_archive(base, additional=()):
    """Minimal amd64 runtime and packages for solver edge cases."""
    base.mkdir(parents=True, exist_ok=True)
    build = base / 'build'
    build.mkdir()
    libc = Path(subprocess.check_output(['cc', '-print-file-name=libc.so.6'], text=True).strip()).resolve()
    loader = Path('/lib64/ld-linux-x86-64.so.2').resolve()
    packages = [deb(build, 'libc6', '1', files={
        '/usr/lib/x86_64-linux-gnu/libc.so.6': libc,
        '/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2': loader,
        '/usr/lib64/ld-linux-x86-64.so.2': ('../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2',)}),
        deb(build, 'libxrandr2'),
        deb(build, 'chosen', '2:1.0-3', depends='leaf', extra='Provides: virtual-abi (= 7)\nMulti-Arch: allowed\n'),
        deb(build, 'leaf', arch='all'),
        deb(build, 'foreign-helper', extra='Multi-Arch: foreign\n'),
        deb(build, 'unversioned-provider', extra='Provides: unversioned-abi\n'),
        deb(build, 'collision', extra='Conflicts: chosen\n'),
        deb(build, 'wrong-only', arch='arm64')]
    packages += list(additional)
    repo = base / 'repo'
    pool = repo / 'pool'
    pool.mkdir(parents=True)
    for path in packages:
        shutil.copy(path, pool)
    index = repo / 'dists/fixture/main/binary-amd64/Packages'
    index.parent.mkdir(parents=True)
    index.write_bytes(subprocess.check_output(['dpkg-scanpackages', '--multiversion', 'pool', '/dev/null'], cwd=repo,
                                             stderr=subprocess.DEVNULL))
    release = repo / 'dists/fixture/Release'
    data = index.read_bytes()
    release.write_text('Origin: Link gate fixture\nLabel: Link gate fixture\nSuite: fixture\nCodename: fixture\n'
                       'Architectures: amd64\nComponents: main\nDate: Mon, 26 Oct 2026 00:00:00 UTC\n'
                       f'SHA256:\n {hashlib.sha256(data).hexdigest()} {len(data)} main/binary-amd64/Packages\n')
    keywork = tempfile.TemporaryDirectory(prefix='lc-key-', dir='/tmp')
    gnupg = Path(keywork.name)
    env = {'PATH': '/usr/bin:/bin', 'GNUPGHOME': str(gnupg), 'LC_ALL': 'C'}
    subprocess.run(['gpg', '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
                    '--quick-generate-key', 'Archive fixture', 'ed25519', 'sign', '0'],
                   env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    keyring = base / 'fixture-public.gpg'
    keyring.write_bytes(subprocess.check_output(['gpg', '--batch', '--export'], env=env))
    subprocess.run(['gpg', '--batch', '--yes', '--pinentry-mode', 'loopback', '--passphrase', '',
                    '--clearsign', '--output', str(release.with_name('InRelease')), str(release)],
                   env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['gpgconf', '--kill', 'gpg-agent'], env=env, check=True)
    keywork.cleanup()
    config = base / 'archive.json'
    config.write_text(json.dumps([{'uri': repo.as_uri(), 'suite': 'fixture', 'components': ['main'],
                                  'keyring': str(keyring)}]))
    return config
