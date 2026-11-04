#!/usr/bin/env python3
"""Build a tiny repository tree for the supply-chain test: three binary packages of two sources, one with a
Lean Code record and DEP-5 copyright, one with a free-form copyright, one architecture:all package whose
copyright file is a symlink to its sibling's. Usage: make-fixture.py OUT_DIR  (needs dpkg-deb)."""
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

out = Path(sys.argv[1])
if out.exists():
    shutil.rmtree(out)
pool = out / 'pool/main/f/fixture'
pool.mkdir(parents=True)
work = out.parent / (out.name + '.work')
work.mkdir(exist_ok=True)

DEP5 = """Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: fixture

Files: *
Copyright: 2026 Someone
License: GPL-2+ or Artistic-2.0, and BSD-3-clause

Files: debian/*
Copyright: 2026 Daniel Ramos
License: GPL-2+

Files: vendor/*
Copyright: 2020 Other
License: Strange-1.0

License: GPL-2+
 This program is free software; see /usr/share/common-licenses/GPL-2.

License: Strange-1.0
 Permission is granted to do strange things.
"""


def deb(name, ver, arch, source, extra_ctl, files, links=()):
    root = work / ('%s_%s_%s' % (name, ver, arch))
    if root.exists():
        shutil.rmtree(root)
    (root / 'DEBIAN').mkdir(parents=True)
    ctl = 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\n' % (name, ver, arch)
    if source:
        ctl += 'Source: %s\n' % source
    ctl += extra_ctl + 'Description: fixture package %s\n long text\n' % name
    (root / 'DEBIAN/control').write_text(ctl)
    for p, content in files.items():
        f = root / p
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(content)
    for p, target in links:
        f = root / p
        f.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target, f)
    dest = pool / ('%s_%s_%s.deb' % (name, ver.split(':')[-1], arch))
    subprocess.run(['dpkg-deb', '-Zxz', '--root-owner-group', '--build', str(root), str(dest)], check=True, capture_output=True)
    return dest


lc = {'architecture': 'amd64', 'format': 'lc1', 'hr_package': 'alpha-lc-hr', 'package': 'alpha', 'scope': 'qualified-installed-payload',
      'version': '1.0-1+stereo3d1+lc1', 'renderer': {'identity': 'lean 0.1.24', 'sha256': 'a' * 64},
      'files': [{'path': '/usr/share/alpha/a.conf', 'status': 'projected', 'sha256': 'b' * 64, 'sha_hr': 'c' * 64, 'bytes': 3},
                {'path': '/usr/bin/alpha', 'status': 'left', 'sha256': 'd' * 64, 'reason': 'binary', 'bytes': 3}]}
d1 = deb('alpha', '1.0-1+stereo3d1+lc1', 'amd64', 'fixsrc (1.0-1+stereo3d1+lc1)',
         'Original-Maintainer: Debian Qt/KDE Maintainers <debian-qt-kde@lists.debian.org>\nHomepage: https://example.org/alpha\n',
         {'usr/share/doc/alpha/copyright': DEP5, 'usr/share/dpkg-stereo/lc/alpha/amd64.json': json.dumps(lc)})
d2 = deb('alpha-lc-hr', '1.0-1+stereo3d1+lc1', 'amd64', 'fixsrc (1.0-1+stereo3d1+lc1)', '',
         {'usr/share/doc/alpha-lc-hr/copyright': 'free form text, no format line\n'})
d3 = deb('alpha-data', '1.0-1+stereo3d1+lc1', 'all', 'fixsrc (1.0-1+stereo3d1+lc1)', '', {},
         links=[('usr/share/doc/alpha-data/copyright', '../alpha-lc-hr/copyright')])
d4 = deb('beta', '2.0', 'amd64', None, '', {'usr/share/doc/beta/copyright': DEP5.replace('Strange-1.0', 'MIT')})


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def dsc(name, ver, orig):
    t = pool / ('%s_%s.orig.tar.xz' % (name, ver.split('-')[0]))
    t.write_bytes(b'tarball of ' + name.encode())
    text = 'Format: 3.0 (quilt)\nSource: %s\nBinary: x\nArchitecture: any\nVersion: %s\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\n' % (name, ver)
    text += 'Checksums-Sha256:\n %s %d %s\n' % (sha(t), t.stat().st_size, t.name)
    text += 'Files:\n %s %d %s\n' % (hashlib.md5(t.read_bytes()).hexdigest(), t.stat().st_size, t.name)
    (pool / ('%s_%s.dsc' % (name, ver.split(':')[-1]))).write_text(text)


dsc('fixsrc', '1.0-1+stereo3d1+lc1', None)
dsc('beta', '2.0', None)

entries = []
for d in (d1, d2, d3, d4):
    ctl = subprocess.run(['dpkg-deb', '-f', str(d)], capture_output=True, text=True, check=True).stdout.rstrip('\n')
    entries.append('%s\nFilename: %s\nSize: %d\nSHA256: %s\n' % (ctl, d.relative_to(out), d.stat().st_size, sha(d)))
for arch in ('amd64', 'all'):
    bdir = out / 'dists/mashtabba/main' / ('binary-' + arch)
    bdir.mkdir(parents=True)
    sel = [e for e in entries if ('Architecture: %s' % arch) in e]
    with gzip.open(bdir / 'Packages.gz', 'wt') as f:
        f.write('\n'.join(sel))
shutil.rmtree(work)
print('fixture at', out)
