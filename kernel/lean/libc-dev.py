#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Stage the edition's linux-libc-dev, and Debian's linux-libc-dev-ARCH-cross set, from the kernel source it was built from.

    libc-dev.py SOURCE-TREE WORK-DIR STAGE-DIR [CROSS-DIR]
    libc-dev.py --cross-from-installed CROSS-DIR

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

With CROSS-DIR it also stages, from the same files, the 30 linux-libc-dev-ARCH-cross packages that
Debian's linux source builds next to linux-libc-dev (ORDER 256): the "sysroot" layout cross compilers
search, /usr/GNU-TYPE/include, as relative links into linux-libc-dev's own files, one package per
Debian architecture, in CROSS-DIR/PACKAGE/. --cross-from-installed makes the same packages from the
linux-libc-dev installed on the build system (its dpkg file list), for a source that is not the kernel's.
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

# Debian's cross set, as src:linux builds it since 6.18~rc4-1~exp1 ("Take over linux-libc-dev-*-cross from
# cross-toolchain-base, see #1065416"): Debian architecture -> (GNU type, kernel architecture), from
# linux 7.2.11-1 debian/rules.gen (ALL_LIBCDEV_SPEC_CROSS) and debian/linux-libc-dev-*-cross.install. The
# directory is the GNU type, not the multiarch triplet, since 7.2~rc7-1~exp1 (#1144100: i686-linux-gnu for i386).
CROSS = {
    'alpha': ('alpha-linux-gnu', 'alpha'),
    'amd64': ('x86_64-linux-gnu', 'x86'),
    'arc': ('arc-linux-gnu', 'arc'),
    'arm64': ('aarch64-linux-gnu', 'arm64'),
    'armel': ('arm-linux-gnueabi', 'arm'),
    'armhf': ('arm-linux-gnueabihf', 'arm'),
    'hppa': ('hppa-linux-gnu', 'parisc'),
    'i386': ('i686-linux-gnu', 'x86'),
    'loong64': ('loongarch64-linux-gnu', 'loongarch'),
    'm68k': ('m68k-linux-gnu', 'm68k'),
    'mips': ('mips-linux-gnu', 'mips'),
    'mips64': ('mips64-linux-gnuabi64', 'mips'),
    'mips64el': ('mips64el-linux-gnuabi64', 'mips'),
    'mips64r6': ('mipsisa64r6-linux-gnuabi64', 'mips'),
    'mips64r6el': ('mipsisa64r6el-linux-gnuabi64', 'mips'),
    'mipsel': ('mipsel-linux-gnu', 'mips'),
    'mipsn32': ('mips64-linux-gnuabin32', 'mips'),
    'mipsn32el': ('mips64el-linux-gnuabin32', 'mips'),
    'mipsn32r6': ('mipsisa64r6-linux-gnuabin32', 'mips'),
    'mipsn32r6el': ('mipsisa64r6el-linux-gnuabin32', 'mips'),
    'mipsr6': ('mipsisa32r6-linux-gnu', 'mips'),
    'mipsr6el': ('mipsisa32r6el-linux-gnu', 'mips'),
    'powerpc': ('powerpc-linux-gnu', 'powerpc'),
    'ppc64': ('powerpc64-linux-gnu', 'powerpc'),
    'ppc64el': ('powerpc64le-linux-gnu', 'powerpc'),
    'riscv64': ('riscv64-linux-gnu', 'riscv'),
    's390x': ('s390x-linux-gnu', 's390'),
    'sh4': ('sh4-linux-gnu', 'sh'),
    'sparc64': ('sparc64-linux-gnu', 'sparc'),
    'x32': ('x86_64-linux-gnux32', 'x86'),
}
STORE = 'usr/lib/linux/uapi/'
SHARED = 'usr/include/'


def cross_package(debian_arch):
    return f'linux-libc-dev-{debian_arch}-cross'


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


def cross_links(files):
    """Debian's do_symlink farms (debian/rules.real, target build_libc-dev): for each Debian architecture, a link
    /usr/GNU-TYPE/include/PATH to every shared header /usr/include/PATH (taken before the multiarch links exist,
    so the triplet directories are not part of it) and to every file /usr/lib/linux/uapi/KERNEL-ARCH/PATH of the
    architecture's store (asm/...). FILES are linux-libc-dev's regular files, relative to the root."""
    shared = sorted(f for f in files if f.startswith(SHARED) and f.split('/')[2] not in TRIPLETS)
    if not any(f == SHARED + 'drm/drm_mode.h' for f in shared):
        raise SystemExit('no usr/include/drm/drm_mode.h among the shared headers')
    for debian_arch, (gnu_type, kernel_arch) in sorted(CROSS.items()):
        prefix = f'{STORE}{kernel_arch}/'
        store = sorted(f for f in files if f.startswith(prefix))
        if not any(f.startswith(prefix + 'asm/') for f in store):
            raise SystemExit(f'{debian_arch}: no {prefix}asm/ store')
        links = {}
        for relative, target in [(f[len(SHARED):], f) for f in shared] + [(f[len(prefix):], f) for f in store]:
            link = f'usr/{gnu_type}/include/{relative}'
            if link in links:
                raise SystemExit(f'{debian_arch}: {link} would link two files')
            links[link] = target
        yield cross_package(debian_arch), links


def write_cross(files, root, out):
    """Write the links of cross_links(FILES) into OUT/PACKAGE/, relative, as `ln -sr` makes them; every target
    must be a regular file of ROOT. OUT must be new."""
    if out.exists():
        raise SystemExit(f'{out} exists; the cross directory must be new')
    total = 0
    for package, links in cross_links(files):
        for link, target in sorted(links.items()):
            if not (root / target).is_file() or (root / target).is_symlink():
                raise SystemExit(f'{package}: {target} is not a regular file of {root}')
            path = out / package / link
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(os.path.relpath('/' + target, '/' + os.path.dirname(link)))
        total += len(links)
    for path in sorted(out.rglob('*')):
        if path.is_dir() and not path.is_symlink():
            path.chmod(0o755)
    print(f'linux-libc-dev-*-cross staged: {len(CROSS)} packages, {total} links')


def stage_files(stage):
    return sorted(p.relative_to(stage).as_posix() for base in (SHARED, STORE)
                  for p in (stage / base).rglob('*') if p.is_file() and not p.is_symlink())


def installed_files(package='linux-libc-dev'):
    listed = subprocess.run(['dpkg-query', '-L', package], check=True, capture_output=True, text=True).stdout
    return sorted(line[1:] for line in listed.splitlines()
                  if line.startswith(('/' + SHARED, '/' + STORE)) and os.path.isfile(line) and not os.path.islink(line))


def main(source, work, stage, cross=None):
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
    # the cross farms are made before the multiarch links, as Debian's rules.real does (the triplet
    # directories of /usr/include are not shared headers)
    if cross is not None:
        write_cross(stage_files(stage), stage, Path(cross).resolve())
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
    if len(sys.argv) == 3 and sys.argv[1] == '--cross-from-installed':
        write_cross(installed_files(), Path('/'), Path(sys.argv[2]).resolve())
    elif len(sys.argv) in (4, 5):
        main(*sys.argv[1:])
    else:
        raise SystemExit(__doc__)
