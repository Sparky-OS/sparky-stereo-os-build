#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
"""boot-kernels.py ROOT [ROOT ...] : lists a system's /boot and its installed kernel packages, and fails when a
kernel that is not the edition's is there.

The edition ships only its own kernels (Daniel, 2026-10-24: Debian's kernel has no stereo 3D, so it is not shipped
with the distribution): linux-image-sparky-stereo and its flavours, whose releases end in -stereo3dN, -stereo3dN-v3
or -rt-stereo3dN. A Debian kernel is any installed linux-image, linux-headers, linux-binary, linux-modules,
linux-signed or versioned linux-base package for amd64 (linux-image-amd64 and the versioned ones it brings; plain
linux-base is the kernel tools every kernel uses), and any /boot file of a release the edition does not build.
ROOT is a root file system: the image's tree, an unpacked squashfs, an installed disk.
Exit status: 0 when every ROOT holds only edition kernels and at least one, 1 otherwise.
"""
import os
import re
import sys

EDITION_RELEASE = re.compile(r'-(rt-)?stereo3d\d+(-v3)?$')
DEBIAN_KERNEL_PACKAGE = re.compile(r'^linux-(image|headers|binary|modules|signed|base)-.*amd64(-unsigned)?$')
BOOT_FILE = re.compile(r'^(vmlinuz|initrd\.img|config|System\.map)-(.+)$')


def installed(root):
    found = []
    try:
        text = open(os.path.join(root, 'var/lib/dpkg/status'), encoding='utf-8', errors='replace').read()
    except FileNotFoundError:
        return None
    for stanza in text.split('\n\n'):
        fields = dict(re.findall(r'^([A-Za-z-]+): (.*)$', stanza, re.M))
        if fields.get('Status', '').endswith(' installed') and fields.get('Package', '').startswith('linux-'):
            found.append((fields['Package'], fields.get('Version', '')))
    return sorted(found)


def check(root):
    bad = []
    print('== %s' % root)
    boot = os.path.join(root, 'boot')
    names = sorted(os.listdir(boot)) if os.path.isdir(boot) else []
    print('-- /boot')
    kernels = 0
    for n in names:
        m = BOOT_FILE.match(n)
        verdict = ''
        if m:
            if EDITION_RELEASE.search(m.group(2)):
                verdict = 'edition'
                kernels += m.group(1) == 'vmlinuz'
            else:
                verdict = 'NOT THE EDITION\'S'
                bad.append('/boot/' + n)
        print('   %-48s %s' % (n, verdict))
    packages = installed(root)
    print('-- installed linux-* packages')
    if packages is None:
        print('   (no dpkg status file)')
    else:
        for p, v in packages:
            verdict = ''
            if DEBIAN_KERNEL_PACKAGE.match(p):
                verdict = 'DEBIAN KERNEL'
                bad.append(p)
            print('   %-48s %-28s %s' % (p, v, verdict))
    if not kernels:
        bad.append('no edition kernel in /boot')
    print('-- %s' % ('FAIL: ' + ', '.join(bad) if bad else 'PASS: only edition kernels (%d)' % kernels))
    return not bad


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ok = [check(r) for r in sys.argv[1:]]
    sys.exit(0 if all(ok) else 1)


if __name__ == '__main__':
    main()
