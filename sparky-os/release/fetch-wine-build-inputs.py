#!/usr/bin/env python3
"""Retain exact Wine 10 build inputs from Debian's authenticated stable index."""
from pathlib import Path
import hashlib
import json
import lzma
import subprocess
import urllib.request
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

root = (cfg.path('SPARKY_MIGRATION_WORK') / 'wine-build-inputs')
subprocess.run(['gpgv', '--keyring', '/usr/share/keyrings/debian-archive-keyring.gpg',
                str(root / 'InRelease')], check=True)
release = (root / 'InRelease').read_text()
records = []
for arch in ['amd64', 'i386']:
    wanted = {'unicode-data', 'unicode-idna', 'unicode-cldr-core', 'libldap2-dev',
              'libcapi20-dev', 'libcapi20-3t64'}
    index_path = f'main/binary-{arch}/Packages.xz'
    checksum, size, _ = next(line.split() for line in release.splitlines()
                             if line.endswith(' ' + index_path) and len(line.split()[0]) == 64)
    index = root / f'trixie-{arch}-Packages.xz'
    if not index.exists():
        urllib.request.urlretrieve(
            f'https://deb.debian.org/debian/dists/trixie/main/binary-{arch}/by-hash/SHA256/{checksum}', index)
    assert index.stat().st_size == int(size)
    assert hashlib.sha256(index.read_bytes()).hexdigest() == checksum
    for paragraph in lzma.decompress(index.read_bytes()).decode().split('\n\n'):
        fields = dict(line.split(': ', 1) for line in paragraph.splitlines()
                      if ': ' in line and not line.startswith(' '))
        name = fields.get('Package')
        if name not in wanted:
            continue
        wanted.remove(name)
        if arch == 'i386' and fields['Architecture'] == 'all':
            continue
        archive = root / Path(fields['Filename']).name
        if not archive.exists():
            urllib.request.urlretrieve('https://deb.debian.org/debian/' + fields['Filename'], archive)
        assert archive.stat().st_size == int(fields['Size'])
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == fields['SHA256']
        (root / f'{name}-{fields["Architecture"]}-record.txt').write_text(paragraph + '\n')
        records.append(dict(package=name, version=fields['Version'], architecture=fields['Architecture'],
                            filename=archive.name, sha256=fields['SHA256'], size=int(fields['Size']),
                            index_sha256=checksum, index=index_path,
                            source='Debian trixie signed InRelease and package index'))
    assert not wanted, wanted
(root / 'verified-packages.json').write_text(json.dumps(records, indent=2) + '\n')
print([(r['package'], r['version'], r['architecture']) for r in records])
