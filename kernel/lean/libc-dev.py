#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Stage the edition's linux-libc-dev from the kernel source it was built from (ORDER 222).

    libc-dev.py SOURCE-TREE WORK-DIR STAGE-DIR

Debian's linux-libc-dev (source package linux, architecture all, Multi-Arch: foreign) holds the
userspace API headers of every architecture glibc supports: the headers all architectures share in
/usr/include (linux/, asm-generic/, drm/, ...), the architecture-specific asm/ headers once per kernel
architecture in /usr/lib/linux/uapi/ARCH/asm/, and one directory per Debian multiarch triplet in
/usr/include/TRIPLET/asm/ whose files are symbolic links into that store. This script makes the same
layout from our patched tree, so that libdrm, KWin and glibc built in the edition see our UAPI
(drivers' struct drm_hdmi_3d_metadata and the "HDMI 3D metadata" connector property of series group 34).

Every architecture runs the kernel's own `make headers_install` (scripts/headers_install.sh, with
unifdef): the stripped headers are what the kernel promises userspace, nothing is copied by hand.
The headers all architectures share must be byte for byte the same wherever an architecture has them
(an architecture without KVM has no linux/kvm.h; the shared set is the union), or the script stops: a
header that differs by architecture needs a decision, not a guess.

Triplets and the kernel architecture each one takes are Debian's, read from linux-libc-dev 7.2.11-1
(readlink of asm/unistd.h in every triplet directory).
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

TRIPLETS = {
    'aarch64-linux-gnu': 'arm64',
    'alpha-linux-gnu': 'alpha',
    'arm-linux-gnueabi': 'arm',
    'arm-linux-gnueabihf': 'arm',
    'hppa-linux-gnu': 'parisc',
    'i386-linux-gnu': 'x86',
    'loongarch64-linux-gnu': 'loongarch',
    'm68k-linux-gnu': 'm68k',
    'mips-linux-gnu': 'mips',
    'mips64-linux-gnuabi64': 'mips',
    'mips64el-linux-gnuabi64': 'mips',
    'mipsel-linux-gnu': 'mips',
    'mipsisa64r6el-linux-gnuabi64': 'mips',
    'powerpc-linux-gnu': 'powerpc',
    'powerpc64-linux-gnu': 'powerpc',
    'powerpc64le-linux-gnu': 'powerpc',
    'riscv64-linux-gnu': 'riscv',
    's390x-linux-gnu': 's390',
    'sh4-linux-gnu': 'sh',
    'sparc64-linux-gnu': 'sparc',
    'x86_64-linux-gnu': 'x86',
    'x86_64-linux-gnux32': 'x86',
}
# Debian ships the arc store without a triplet (no Debian port); keep the same set.
KERNEL_ARCHES = sorted(set(TRIPLETS.values()) | {'arc'})
REFERENCE = 'x86'
LEFTOVERS = {'.install', '..install.cmd'}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def install_headers(source, work, arch):
    obj = work / ('hdr-' + arch)
    dest = obj / 'dest'
    shutil.rmtree(obj, ignore_errors=True)
    obj.mkdir(parents=True)
    subprocess.run(['make', '-s', '-C', str(source), f'O={obj}', f'ARCH={arch}', 'headers_install',
                    f'INSTALL_HDR_PATH={dest}', '-j2'], check=True)
    include = dest / 'include'
    for leftover in list(include.rglob('*')):
        if leftover.name in LEFTOVERS:
            leftover.unlink()
    return include


def tree(path):
    return {p.relative_to(path).as_posix(): sha256(p)
            for p in sorted(path.rglob('*')) if p.is_file() and p.relative_to(path).parts[0] != 'asm'}


def main(source, work, stage):
    source, work, stage = (Path(arg).resolve() for arg in (source, work, stage))
    if stage.exists():
        raise SystemExit(f'{stage} exists; the stage directory must be new')
    work.mkdir(parents=True, exist_ok=True)
    store = stage / 'usr/lib/linux/uapi'
    include_dir = stage / 'usr/include'
    common = {}
    for arch in [REFERENCE] + [a for a in KERNEL_ARCHES if a != REFERENCE]:
        include = install_headers(source, work, arch)
        files = tree(include)
        for relative, digest in files.items():
            if relative in common and common[relative] != digest:
                raise SystemExit(f'{arch}: {relative} differs from the {REFERENCE} one; the shared headers must be identical')
            if relative not in common:
                # an architecture without KVM, say, lacks linux/kvm.h: the shared set is the union
                common[relative] = digest
                target = include_dir / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(include / relative, target)
        asm = include / 'asm'
        if not asm.is_dir():
            raise SystemExit(f'{arch}: headers_install produced no asm/')
        out = store / arch / 'asm'
        shutil.copytree(asm, out, symlinks=True, dirs_exist_ok=True)  # riscv has asm/vendor/
        shutil.rmtree(work / ('hdr-' + arch))
    for triplet, arch in sorted(TRIPLETS.items()):
        base = store / arch / 'asm'
        directory = include_dir / triplet / 'asm'
        # every file of the architecture's store is linked from the triplet; a subdirectory
        # (riscv's asm/vendor/) is a real directory of links, as in Debian's package
        for entry in sorted(p for p in base.rglob('*') if not p.is_dir()):
            relative = entry.relative_to(base)
            link = directory / relative
            link.parent.mkdir(parents=True, exist_ok=True)
            depth = len(relative.parts) - 1
            link.symlink_to('../' * (3 + depth) + f'lib/linux/uapi/{arch}/asm/{relative.as_posix()}')
    for path in sorted(stage.rglob('*')):
        if path.is_dir() and not path.is_symlink():
            path.chmod(0o755)
        elif path.is_file() and not path.is_symlink():
            path.chmod(0o644)
    print(f'linux-libc-dev staged: {len(common)} common headers, {len(KERNEL_ARCHES)} architectures, '
          f'{len(TRIPLETS)} multiarch directories')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
