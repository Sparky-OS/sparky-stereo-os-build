#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Red and green for kernel/qualification/orig_archive.py (ORDER 636).

    test.py [SOURCE_DIR]

Two copies of one tree that differ only in what an export or a restore changes (file times, the order the files were
written in, the modes a 002 umask gives) are packed twice:
  red:   with the packing prepare-kernel-source.py used up to build 17 (plain tar): the two archives must differ;
  green: with orig_archive.pack: the two archives must be the same bytes.
Without SOURCE_DIR a small fixture tree is made; with it (an unpacked kernel source) the real tree is copied twice.
Exit status 0 only when red differs and green is equal.
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'qualification'))
import orig_archive

STAMP = 1793362192


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def old_pack(source, archive, top):
    with open(archive, 'wb') as sink:
        packed = subprocess.Popen(['tar', '-C', str(source), '--exclude=./debian',
                                   '--transform=flags=r;s,^\\.,' + top + ',', '-cf', '-', '.'], stdout=subprocess.PIPE)
        compressed = subprocess.Popen(['xz', '-T2', '-3'], stdin=packed.stdout, stdout=sink)
        packed.stdout.close()
        assert compressed.wait() == 0 and packed.wait() == 0


def fixture(root):
    for rel, text in [('Makefile', 'all:\n'), ('net/ipv4/tcp.c', 'int tcp;\n'), ('scripts/run.sh', '#!/bin/sh\n'),
                      ('debian/control', 'Source: x\n'), ('include/a.h', '#define A 1\n')]:
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    (root / 'scripts/run.sh').chmod(0o755)


def copy_variant(src, dst, when, writable, reverse):
    names = sorted(p for p in src.rglob('*') if p.is_file())
    for path in (reversed(names) if reverse else names):
        target = dst / path.relative_to(src)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        mode = path.stat().st_mode & 0o777
        os.chmod(target, mode | 0o020 if writable else mode)
        os.utime(target, (when, when))
    for directory in [p for p in dst.rglob('*') if p.is_dir()] + [dst]:
        os.utime(directory, (when, when))


def main():
    work = Path(tempfile.mkdtemp(prefix='orig-reproducible-', dir=os.environ.get('TMPDIR')))
    try:
        src = Path(sys.argv[1]) if len(sys.argv) > 1 else work / 'fixture'
        if len(sys.argv) <= 1:
            fixture(src)
        a, b = work / 'a', work / 'b'
        copy_variant(src, a, 1700000000, False, False)
        copy_variant(src, b, 1800000000, True, True)
        top = 'linux-stereo-test-7.3.4'
        old_pack(a, work / 'red-a.tar.xz', top)
        old_pack(b, work / 'red-b.tar.xz', top)
        orig_archive.pack(a, work / 'green-a.tar.xz', top, STAMP)
        orig_archive.pack(b, work / 'green-b.tar.xz', top, STAMP)
        red = sha(work / 'red-a.tar.xz') != sha(work / 'red-b.tar.xz')
        green = sha(work / 'green-a.tar.xz') == sha(work / 'green-b.tar.xz')
        print(f'red (packing up to build 17): copies {"differ" if red else "are equal"} '
              f'({sha(work / "red-a.tar.xz")[:12]} {sha(work / "red-b.tar.xz")[:12]})')
        print(f'green (orig_archive.pack): copies {"are equal" if green else "differ"} '
              f'({sha(work / "green-a.tar.xz")[:12]} {sha(work / "green-b.tar.xz")[:12]})')
        listing = subprocess.run(['tar', '-tvJf', str(work / 'green-a.tar.xz')], capture_output=True, text=True,
                                 check=True).stdout.splitlines()
        print('green listing, first lines:', *listing[:3], sep='\n  ')
        return 0 if red and green else 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    raise SystemExit(main())
