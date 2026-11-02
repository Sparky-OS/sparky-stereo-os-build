#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/30
"""old-kernels.py ROOT RELEASE : prints, one per line, the installed packages of every edition kernel in ROOT whose
release is not RELEASE: linux-image-R and linux-headers-R with their Lean Code -lc-hr companions, installed or
left as configuration files.

The ISO ships one kernel, the one linux-image-sparky-stereo depends on (pack.sh's KV). When a newer edition kernel is
published between the root file system and the pack, the meta's new Depends installs it beside the older one, and
nothing removes the older one; pack.sh purges what this prints. Debian's kernels are boot-kernels.py's matter.
Exit status: 0, with nothing printed when RELEASE is the only edition kernel; 1 on a usage error.
"""
import os
import re
import sys

EDITION_RELEASE = re.compile(r'^\d+\.\d+(?:\.\d+)?(?:-rc\d+)?-(rt-)?stereo3d\d+(-v3)?$')
KERNEL_PACKAGE = re.compile(r'^linux-(?:image|headers)-(.+?)(?:-lc-hr)?$')


def installed(root):
    with open(os.path.join(root, 'var/lib/dpkg/status'), encoding='utf-8', errors='replace') as f:
        text = f.read()
    for stanza in text.split('\n\n'):
        fields = dict(re.findall(r'^([A-Za-z-]+): (.*)$', stanza, re.M))
        status = fields.get('Status', '').split()
        if 'Package' in fields and status and status[-1] != 'not-installed':
            yield fields['Package']


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root, keep = sys.argv[1], sys.argv[2]
    for package in sorted(installed(root)):
        m = KERNEL_PACKAGE.match(package)
        if m and EDITION_RELEASE.match(m.group(1)) and m.group(1) != keep:
            print(package)


if __name__ == '__main__':
    main()
