#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/30
"""kernel-fixes.py ISO-ROOT IMAGE-ROOT : checks that every kernel a packed ISO can boot or install carries the
security fixes in FIXES, and that no older kernel is left anywhere in it.

ISO-ROOT is the ISO's tree (the ISO mounted read-only); IMAGE-ROOT is the image's root file system (its
filesystem.squashfs mounted read-only, or any unpacked tree). Nothing is written. A kernel is found by its release
(uname -r) in:
- the ISO: every /live/vmlinuz* (the release in the kernel's own boot header), every /live/initrd* (the module trees
  it holds), and every kernel, initrd or release the boot menus name (/boot/grub/*.cfg and /isolinux/*.cfg);
- the image: /boot's kernel files and the vmlinuz and initrd.img links, /usr/lib/modules (and /lib/modules when it is
  not merged-/usr's link), DKMS's builds in /var/lib/dkms, and dpkg's database.
Each release must be an installed linux-image-RELEASE package of the edition's kernel sources at or above the
edition's first fixed version, and its upstream version at or above the first upstream release with the fix. Every
package of those sources that dpkg knows (installed, or left as configuration files) must be at or above that
version too: the image holds no older build of the kernel's packages (linux-libc-dev included).
Exit status: 0 when every check passes, 1 otherwise. Needs dpkg (--compare-versions) and the initrd's decompressor.
"""
import glob
import os
import re
import struct
import subprocess
import sys

# a fix: the CVE, the upstream commit, the first upstream release with it (in dpkg's form, X.Y.Z~rcN) and the
# edition's first kernel package version with it.
# CVE-2026-98432: IPv4 TCP use after free (kernel CNA, vulns.git cve/published/2026/CVE-2026-98432.json); Eric Dumazet's
# e3f33b0a1d89 changes net/ipv4/af_inet.c and tcp_ipv4.c, is in v7.3-rc7 and not in v7.3-rc6; the edition's kernel
# series changes neither file, so build 13 (Linux 7.3) is the first edition kernel with it and build 12 (7.3-rc6) lacks it.
FIXES = [
    ('CVE-2026-98432', 'e3f33b0a1d89 "ipv4: free inet_opt and ireq_opt after an RCU grace period"', '7.3.0~rc7', '7.3.0-13+lc1'),
]
# the edition kernel's source packages, one per flavour (sparky-os/release/show-build-status.py names their builds)
KERNEL_SOURCE = re.compile(r'^linux-stereo-(base|v3|rt)$')
RELEASE = re.compile(r'^(\d+)\.(\d+)(?:\.(\d+))?(?:-rc(\d+))?(?=[-+]|$)')
# a release written in a menu's text: an edition release, or any X.Y[.Z]-rcN
RELEASE_TEXT = re.compile(r'(?<![\w.])\d+\.\d+(?:\.\d+)?(?:-rc\d+)?-(?:rt-)?stereo3d\d+(?:-v3)?(?![\w.])|(?<![\w.])\d+\.\d+(?:\.\d+)?-rc\d+(?![\w.])')
BOOT_FILE = re.compile(r'^(?:vmlinuz|vmlinux|initrd\.img|config|System\.map)-(.+)$')
KERNEL_NAME = re.compile(r'^(?:vmlinuz|vmlinux|bzImage)')
INITRD_NAME = re.compile(r'^(?:initrd|initramfs)')
MODULES = re.compile(r'^(?:\./)?(?:usr/)?lib/modules/([^/]+)(?:/|$)')
# the initramfs buffer (Linux's Documentation/driver-api/early-userspace/buffer-format.rst): newc or crc cpio archives,
# each plain or compressed with one of the seven compressors it lists, with any number of zero bytes between them
CPIO_MAGIC = (b'070701', b'070702')
COMPRESSORS = [(b'\x28\xb5\x2f\xfd', ['zstd', '-dcq']), (b'\x1f\x8b', ['gzip', '-dc']), (b'\xfd7zXZ\x00', ['xz', '-dc']),
               (b'\x02\x21\x4c\x18', ['lz4', '-dc']), (b'BZh', ['bzip2', '-dc']), (b'\x5d\x00\x00', ['xz', '--format=lzma', '-dc']),
               (b'\x89LZO\x00', ['lzop', '-dc'])]


def ge(a, b):
    return subprocess.run(['dpkg', '--compare-versions', a, 'ge', b]).returncode == 0


def upstream(release):
    """The upstream version of a release in dpkg's form: 7.3.0-rc6-stereo3d12 is 7.3.0~rc6, 7.3.1-stereo3d14 is 7.3.1."""
    m = RELEASE.match(release)
    if not m:
        return None
    return '%s.%s.%s%s' % (m.group(1), m.group(2), m.group(3) or '0', '~rc' + m.group(4) if m.group(4) else '')


def bzimage_release(path):
    """The release in a kernel's boot header (Documentation/arch/x86/boot.rst: "HdrS" at 0x202; kernel_version at 0x20e,
    a pointer to the NUL-terminated version string "less 0x200"); the release is the string's first word."""
    with open(path, 'rb') as f:
        head = f.read(0x210)
        if len(head) < 0x210 or head[0x202:0x206] != b'HdrS':
            return None, 'not a Linux boot image'
        p = struct.unpack('<H', head[0x20e:0x210])[0]
        if not p:
            return None, 'no version string in its boot header'
        f.seek(p + 0x200)
        text = f.read(256).split(b'\0', 1)[0].decode('ascii', 'replace')
    return (text.split()[0] if text.split() else None), text


class Stream:
    """read(n) over a file or a pipe, with bytes put back and the count of bytes consumed."""

    def __init__(self, read):
        self.raw, self.back, self.pos = read, b'', 0

    def read(self, n):
        data, self.back = self.back[:n], self.back[n:]
        while len(data) < n:
            more = self.raw(n - len(data))
            if not more:
                break
            data += more
        self.pos += len(data)
        return data

    def unread(self, data):
        self.back, self.pos = data + self.back, self.pos - len(data)


def cpio_names(stream, names):
    """Reads newc cpio archives (and the zeros between them) until the end of the stream or the first data that is not
    an archive, which is put back and returned (b'' at the end); appends every member's name."""
    while True:
        b = stream.read(1)
        while b == b'\0':
            b = stream.read(1)
        if not b:
            return b''
        head = b + stream.read(5)
        if head not in CPIO_MAGIC:
            stream.unread(head)
            return head
        rest = stream.read(104)
        if len(rest) < 104:
            return b''
        size, namesize = int(rest[48:56], 16), int(rest[88:96], 16)
        name = stream.read(namesize).rstrip(b'\0').decode('utf-8', 'replace')
        left = (4 - (110 + namesize) % 4) % 4 + size + (4 - size % 4) % 4
        while left:
            chunk = stream.read(min(left, 1 << 20))
            if not chunk:
                return b''
            left -= len(chunk)
        if name != 'TRAILER!!!':
            names.append(name)


def initrd_releases(path):
    """The module trees an initramfs holds: its uncompressed archives (early microcode), then the compressed one."""
    names = []
    with open(path, 'rb') as f:
        stream = Stream(f.read)
        sig = cpio_names(stream, names)
        if sig:
            tool = next((cmd for m, cmd in COMPRESSORS if sig.startswith(m)), None)
            if tool is None:
                return None, 'unknown data at byte %d' % stream.pos
            fd = os.open(path, os.O_RDONLY)
            os.lseek(fd, stream.pos, os.SEEK_SET)
            try:
                proc = subprocess.Popen(tool, stdin=fd, stdout=subprocess.PIPE)
            except FileNotFoundError:
                return None, '%s is needed to read it' % tool[0]
            finally:
                os.close(fd)
            cpio_names(Stream(proc.stdout.read), names)
            proc.stdout.close()
            if proc.wait() != 0:
                return None, '%s failed on it' % tool[0]
    releases = sorted({m.group(1) for m in map(MODULES.match, names) if m})
    return releases, '%d files' % len(names)


def menu_refs(text):
    """The kernel and initrd paths a GRUB or ISOLINUX menu names."""
    kernels, initrds = [], []
    for line in text.splitlines():
        if line.lstrip().startswith('#'):
            continue
        for m in re.finditer(r'(?:^|[\s;])(?:linux|linuxefi|linux16|kernel)\s+(\S+)', line):
            kernels.append(m.group(1))
        for m in re.finditer(r'(?:^|[\s;])(?:initrd|initrdefi|initrd16)\s+([^;]+)', line):
            initrds += [p for p in m.group(1).split() if p.startswith('/')]
        for m in re.finditer(r'(?:^|\s)initrd=(\S+)', line):
            initrds += m.group(1).split(',')
    return ([p for p in kernels if KERNEL_NAME.match(os.path.basename(p))],
            [p for p in initrds if INITRD_NAME.match(os.path.basename(p))])


def dpkg_packages(root):
    """{package: (version, source, status)} for every package dpkg's status file of the image knows."""
    found = {}
    try:
        text = open(os.path.join(root, 'var/lib/dpkg/status'), encoding='utf-8', errors='replace').read()
    except FileNotFoundError:
        return None
    for stanza in text.split('\n\n'):
        fields = dict(re.findall(r'^([A-Za-z-]+): (.*)$', stanza, re.M))
        if 'Package' in fields and not fields.get('Status', '').endswith(' not-installed'):
            found[fields['Package']] = (fields.get('Version', ''), (fields.get('Source') or fields['Package']).split()[0],
                                        fields.get('Status', '').split()[-1] if fields.get('Status') else '')
    return found


def link_release(path):
    target = os.path.basename(os.readlink(path))
    m = BOOT_FILE.match(target)
    return m.group(1) if m else None


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    iso, image = sys.argv[1], sys.argv[2]
    seen = {}
    fails = []

    def saw(release, place):
        seen.setdefault(release, []).append(place)

    def fail(text):
        fails.append(text)
        print('FAIL  ' + text)

    print('-- the kernels on the ISO')
    kernels = set(glob.glob(os.path.join(iso, 'live', 'vmlinu[xz]*')))
    initrds = set(glob.glob(os.path.join(iso, 'live', 'initrd*')))
    menus = sorted(glob.glob(os.path.join(iso, 'boot/grub/*.cfg')) + glob.glob(os.path.join(iso, 'isolinux/*.cfg')))
    for cfg in menus:
        rel = os.path.relpath(cfg, iso)
        text = open(cfg, encoding='utf-8', errors='replace').read()
        ks, rs = menu_refs(text)
        for p in ks + rs:
            full = os.path.join(iso, p.lstrip('/'))
            if not os.path.isfile(full):
                fail('/%s names %s, which the ISO does not have' % (rel, p))
            else:
                (kernels if p in ks else initrds).add(full)
        for r in sorted(set(m.group(0) for m in RELEASE_TEXT.finditer(text))):
            saw(r, '/%s (text)' % rel)
        print('   /%s: kernels %s, initrds %s' % (rel, ' '.join(sorted(set(ks))) or 'none', ' '.join(sorted(set(rs))) or 'none'))
    for k in sorted(kernels):
        r, text = bzimage_release(k)
        print('   /%s: %s' % (os.path.relpath(k, iso), text))
        if r:
            saw(r, '/' + os.path.relpath(k, iso))
        else:
            fail('/%s: %s' % (os.path.relpath(k, iso), text))
    for i in sorted(initrds):
        rs, text = initrd_releases(i)
        print('   /%s: %s, module trees %s' % (os.path.relpath(i, iso), text, ' '.join(rs or []) or 'none'))
        if not rs:
            fail('/%s: no kernel module tree found (%s)' % (os.path.relpath(i, iso), text))
        for r in rs or []:
            saw(r, '/%s (modules)' % os.path.relpath(i, iso))
    if not kernels:
        fail('the ISO has no kernel in /live')

    print('-- the kernels in the image')
    for d in ('', 'boot'):
        top = os.path.join(image, d)
        for n in sorted(os.listdir(top)) if os.path.isdir(top) else []:
            p = os.path.join(top, n)
            m = BOOT_FILE.match(n)
            if m and not os.path.islink(p):
                saw(m.group(1), '/%s' % os.path.join(d, n))
            elif os.path.islink(p) and re.match(r'^(vmlinuz|initrd\.img)(\.old)?$', n):
                r = link_release(p)
                print('   /%s -> %s' % (os.path.join(d, n), os.readlink(p)))
                if r:
                    saw(r, '/%s (link)' % os.path.join(d, n))
    for d in ('usr/lib/modules', 'lib/modules'):
        top = os.path.join(image, d)
        if os.path.islink(os.path.join(image, d.split('/')[0])) or not os.path.isdir(top):
            continue
        for e in sorted(os.scandir(top), key=lambda e: e.name):
            if e.is_dir(follow_symlinks=False):
                saw(e.name, '/%s/%s' % (d, e.name))
    for build in sorted(glob.glob(os.path.join(image, 'var/lib/dkms/*/*/*'))):
        n = os.path.basename(build)
        if os.path.isdir(build) and not os.path.islink(build) and RELEASE.match(n):
            saw(n, '/' + os.path.relpath(build, image))
    packages = dpkg_packages(image)
    if packages is None:
        fail('the image has no dpkg status file')
        packages = {}
    ours = sorted((p, v, s, st) for p, (v, s, st) in packages.items() if KERNEL_SOURCE.match(s))
    for p, v, s, st in ours:
        print('   %-44s %-20s %-18s %s' % (p, v, s, st))
    for r in sorted(seen):
        print('   %-44s %s' % (r, ', '.join(seen[r])))

    for cve, commit, first_upstream, first_edition in FIXES:
        print('-- %s: %s, upstream from %s, the edition from %s' % (cve, commit, first_upstream, first_edition))
        for p, v, s, st in ours:
            if not ge(v, first_edition):
                fail('%s %s (%s, %s) is older than %s, the first with the %s fix' % (p, v, s, st, first_edition, cve))
        for r in sorted(seen):
            up = upstream(r)
            owner = packages.get('linux-image-' + r)
            where = ', '.join(seen[r])
            if up is None:
                fail('%s (%s) is not a kernel release' % (r, where))
            elif not ge(up, first_upstream):
                fail('%s (%s) is Linux %s, older than %s: it lacks the %s fix' % (r, where, up, first_upstream, cve))
            elif owner is None or owner[2] != 'installed' or not KERNEL_SOURCE.match(owner[1]):
                fail('%s (%s) belongs to no installed linux-image-%s of the edition\'s kernel sources' % (r, where, r))
            elif not ge(owner[0], first_edition):
                fail('%s (%s): linux-image-%s %s is older than %s' % (r, where, r, owner[0], first_edition))
            else:
                print('PASS  %s carries the %s fix: Linux %s, linux-image-%s %s (%s)' % (r, cve, up, r, owner[0], where))
        if not seen:
            fail('no kernel found to check for %s' % cve)
        elif not fails:
            print('PASS  every kernel the ISO boots or installs carries the %s fix, and no older kernel is left: %s'
                  % (cve, ' '.join(sorted(seen))))
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
