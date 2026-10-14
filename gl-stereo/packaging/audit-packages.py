#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Fail on missing packages, provenance, runtime API requirements or bad receipts."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import sys

base = Path(sys.argv[1]) if len(sys.argv)>1 else Path('/build/sources')
all_savers = '--all-savers' in sys.argv
expected = {'gl-stereo':'0.2.0-1', 'kscreenlocker':'6.7.4-1+stereo3d1',
            'plasma-desktop':'4:6.7.4-1+stereo3d1', 'xscreensaver':'6.09+dfsg1-2+stereo3d1'}
if all_savers:
    expected = {'gl-stereo':'0.3.0-1', 'xscreensaver':'6.09+dfsg1-2+stereo3d2'}
credit = 'Sparky Stereo OS, Daniel Ramos\'s edition of SparkyLinux (by Paweł "pavroo" Pijanowski)'
maintainer = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
seen = set()
packages = set()
with tempfile.TemporaryDirectory(prefix='package-audit-', dir='/build') as scratch:
    root = Path(scratch)
    debs = set()
    for source, version in expected.items():
        changes = base / f'{source}_{version.split(":")[-1]}_amd64.changes'
        in_hashes = False
        for line in changes.read_text().splitlines():
            if not line.startswith(' '):
                in_hashes = line == 'Checksums-Sha256:'
            elif in_hashes:
                digest, size, name = line.split()
                assert Path(name).name == name
                path = base / name
                assert path.stat().st_size == int(size)
                assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
                if path.suffix == '.deb': debs.add(path)
    for deb in sorted(debs):
        fields = {}
        for line in subprocess.check_output(['dpkg-deb','-f',str(deb)],text=True).splitlines():
            if line and not line[0].isspace():
                key, value = line.split(':',1)
                fields[key] = value.strip()
        name = fields['Package']
        source = fields.get('Source',name).split()[0]
        assert source in expected, (deb,source)
        assert fields['Version'] == expected[source], (name,fields['Version'])
        assert fields['Maintainer'] == maintainer, name
        assert fields['Comment'] == credit, name
        if source != 'gl-stereo': assert fields.get('Original-Maintainer'), name
        if not name.endswith('-dbgsym'): assert fields['Homepage']=='https://sparkylinux.org', name
        if name in ('gl-stereo','libstereoshow1'):
            assert 'libstereo-declare1 (>= 1.1.0)' in fields['Depends'], fields
        if name == 'gl-stereo':
            assert 'libgl1' in fields['Depends'] and 'libegl1' in fields['Depends'], fields
        seen.add(source)
        packages.add(name)
        subprocess.run(['dpkg-deb','-x',str(deb),scratch],check=True)
    assert seen == set(expected), seen
    for name in packages:
        path = root/'usr/share/doc'/name/'copyright'
        assert credit in ' '.join(path.read_text().split()), (name,'copyright')
    for entry in json.loads((root/'usr/share/gl-stereo/catalogue.json').read_text()):
        for path, digest in ((entry['command'][0],entry['executable_sha256']), (entry['library'],entry['library_sha256'])):
            assert hashlib.sha256((root/path.lstrip('/')).read_bytes()).hexdigest()==digest, (entry['id'],path)
    entries = json.loads((root/'usr/share/gl-stereo/catalogue.json').read_text())
    if all_savers:
        index = json.loads((root/'usr/share/gl-stereo/savers.json').read_text())
        ids = {entry['id'] for entry in index if entry['kind']=='hack'}
        assert len(entries)==len(ids)==132
        assert {entry['id'] for entry in entries}==ids
        from collections import Counter
        assert Counter(entry['qualification']['group'] for entry in entries)==dict(layer=120, flat=10, **{'owning-fix':2})
        assert all(entry['qualification']['state']=='qualified' for entry in index if entry['kind']=='hack')
    else:
        assert {entry['id'] for entry in entries} == {'starfield','rocks','gears','molecule','rubik'}
print('PASS:', len(packages), 'binary packages;', len(expected), 'source versions, provenance, API dependencies and',len(entries),'final receipts')
