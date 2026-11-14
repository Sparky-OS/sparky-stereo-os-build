#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
"""Extend the +22 source's EGL and Vulkan packages with their own problem messages."""
from pathlib import Path
import sys
source, out = map(Path, sys.argv[1:])
def replace_once(s, a, b):
    if s.count(a)!=1: raise SystemExit(f'expected one packaging anchor: {a!r}')
    return s.replace(a,b)
for name in ('control','control.in'):
    s=(source/name).read_text()
    s=replace_once(s,'Package: libegl-mesa0\nSection: libs\nArchitecture: any\nDepends:\n',
      'Package: libegl-mesa0\nSection: libs\nArchitecture: any\nDepends:\n sparky-stereo-problems (>= 0.1.2) [amd64],\n')
    a=s.index('Package: mesa-vulkan-layer-stereo\n'); before=s[:a]; p=s[a:]
    p=replace_once(p,'Depends: libvulkan1,','Depends: sparky-stereo-problems (>= 0.1.2), libvulkan1,')
    (out/name).write_text(before+p)
s=(source/'rules').read_text()
a='\t\t--subject LOCAL1 --subject LOCAL3=LOCAL4\n'
add=''
for package in ('libegl-mesa0','mesa-vulkan-layer-stereo'):
    add+=f'\tinstall -m755 -d debian/{package}/usr/lib/systemd/catalog\n'
    add+=f'\tsparky-stereo-problems catalog {package} debian/lang-pair debian/{package}/usr/lib/systemd/catalog --subject LOCAL1\n'
    (out/(package+'.postrm')).write_text('''#!/bin/sh
set -e
if { [ "$1" = remove ] || [ "$1" = purge ]; } && command -v sparky-stereo-problems >/dev/null 2>&1; then
    sparky-stereo-problems clear --all PACKAGE ||
        echo "PACKAGE: its kept problems could not be ended" >&2
fi
#DEBHELPER#
exit 0
'''.replace('PACKAGE',package))
(out/'rules').write_text(replace_once(s,a,a+add))
