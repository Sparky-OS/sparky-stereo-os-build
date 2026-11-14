#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
"""Make 24.1.15 +stereo3d1 from the accepted +stereo3d5 series and Debian's packaging.

Run in the build container: rebase-source.py STAGED.dsc UPSTREAM.tar.xz DEBIAN.tar.xz OUT
The input archives stay unchanged. OUT must not exist. The source date belongs to this recipe.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
TOOLKIT = HERE.parent.parent
sys.path.insert(0, str(TOOLKIT / 'repo'))
import reproducible


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def checked(path, digest):
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        sys.exit(f'input SHA-256 mismatch: {path}')


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    staged, upstream, packaging, out = [Path(a).resolve() for a in sys.argv[1:]]
    checked(staged, '5e13cb8921d6b80f2d72ef6a7ab05861c7216ee8b8bc29f1d683bd31597588e5')
    checked(upstream, '7311b4bcda22cfc19cb99680eb1c35cfc1ea885981310639f0429fe2948c122e')
    checked(packaging, '136bff293a35772db0497bc8b2720605a323aefcda3dfb48fb19512b04b6e481')
    stamp = reproducible.recipe_epoch([HERE])
    os.environ.update(SOURCE_DATE_EPOCH=str(stamp), DEBFULLNAME='Daniel Ramos (Capitain Jack)',
                      DEBEMAIL='Capitain_Jack@yahoo.com')
    out.mkdir()
    with tempfile.TemporaryDirectory(prefix='xwayland-rebase-', dir=out) as scratch:
        work = Path(scratch)
        old = work / 'staged'
        run('dpkg-source', '--skip-patches', '-x', str(staged), str(old))
        with tarfile.open(upstream) as archive:
            archive.extractall(work, filter='data')
        tree = work / 'xwayland-24.1.15'
        with tarfile.open(packaging) as archive:
            archive.extractall(tree, filter='data')
        deb = tree / 'debian'
        # Debian 24.1.14 changes only its new changelog stanza. Retain that stanza and our entire accepted history.
        changelog = (deb / 'changelog').read_text()
        anchor = 'xwayland (2:24.1.13-1)'
        assert changelog.count(anchor) == 1
        (deb / 'changelog').write_text(changelog.split(anchor)[0] + (old / 'debian/changelog').read_text())
        series = (old / 'debian/patches/series').read_text()
        (deb / 'patches/series').write_text(series)
        for name in series.splitlines():
            if name and not name.startswith('#'):
                shutil.copy2(HERE / 'patches' / name, deb / 'patches' / name)
        control = (deb / 'control').read_text()
        anchor = ' wayland-protocols,\n'
        assert control.count(anchor) == 1
        added = ''.join(f' {p} <!nocheck>,\n' for p in (
            'libxcb-composite0-dev', 'libxcb-present-dev', 'libxcb1-dev',
            'weston', 'x11-xkb-utils', 'xkb-data'))
        (deb / 'control').write_text(control.replace(anchor, added + anchor))
        date = reproducible.rfc2822(stamp)
        run('dch', '--date', date, '--newversion', '2:24.1.15-1+stereo3d1', '--distribution', 'unstable',
            "Rebase the accepted stereo series onto Xwayland 24.1.15 with Debian 24.1.14-1 packaging; "
            "extend patch 0005 around Michel Dänzer's window-pixmap size check while retaining its height checks. "
            "Keep the stereo Present test in the package build.", cwd=tree)
        # Carry the source-consumer plan if the pinned predecessor has one; never silently drop it.
        plan = old / 'debian/sparky-lean-preserve.json'
        args = ['--preserve-plan', str(plan)] if plan.exists() else []
        run('python3', '-m', 'lean.debian_prepare', str(tree), '2:24.1.15-1+stereo3d1+lc1',
            '--toolkit', str(TOOLKIT), *args, cwd=TOOLKIT)
        run('python3', str(TOOLKIT / 'repo/provenance-files.py'), str(tree), '*.patch')
        shutil.copy2(upstream, work / 'xwayland_24.1.15.orig.tar.xz')
        run('dpkg-source', '--before-build', str(tree))
        reproducible.normalize_tree(tree, stamp)
        run('dpkg-source', '-b', str(tree), cwd=work)
        for path in work.glob('xwayland_24.1.15*'):
            if path.is_file():
                shutil.move(str(path), out / path.name)


if __name__ == '__main__':
    main()
