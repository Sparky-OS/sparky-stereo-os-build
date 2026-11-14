#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
"""The changes of +stereo3d22 to mesa's debian/control, control.in and rules (ORDER 561), for next-source.sh.

debian-changes.py DEBIAN OVERLAY: reads the three files of the +stereo3d21 source's debian folder and writes the changed
ones into OVERLAY. Each anchor must be there exactly once, so a source this recipe does not know stops the build.
"""
import sys

PROBLEMS = 'sparky-stereo-problems (>= 0.1.2) [amd64],'
LIBRARY = '/usr/lib/x86_64-linux-gnu/sparky-stereo-problems/libsparky-stereo-problems.so.0'

CONTROL = [
    # the engine makes the journal catalogs at build time and tells the person at run time; it is an amd64 package
    (' debhelper-compat (= 13),\n', f' debhelper-compat (= 13),\n {PROBLEMS}\n'),
    ('Package: libglx-mesa0\nSection: libs\nArchitecture: any\nDepends:\n libgl1-mesa-dri,\n',
     f'Package: libglx-mesa0\nSection: libs\nArchitecture: any\nDepends:\n libgl1-mesa-dri,\n {PROBLEMS}\n'),
    # an older Xwayland of the edition copies a stereo window's pair and keeps the left eye only
    ('Breaks: glx-diversions (<< 0.8.4~), libopengl-perl (<< 0.6704+dfsg-2)\n',
     'Breaks: glx-diversions (<< 0.8.4~), libopengl-perl (<< 0.6704+dfsg-2), xwayland (<< 2:24.1.15-1+stereo3d2~)\n'),
]
RULES = [
    ('\t-Dglvnd=enabled \\\n', f'\t-Dglvnd=enabled \\\n\t-Dsparky-stereo-problems-library={LIBRARY} \\\n'),
    ('\tdh_install -a\n',
     '\tdh_install -a\n\n'
     '\t# The messages of the problems GLX keeps, as journal catalogs (debian/lang, the ten languages). The engine is an\n'
     '\t# amd64 package; a 32-bit program runs its command, which reads these.\n'
     '  ifeq ($(DEB_HOST_ARCH), amd64)\n'
     '\tinstall -m755 -d debian/libglx-mesa0/usr/lib/systemd/catalog\n'
     '\tsparky-stereo-problems catalog libglx-mesa0 debian/lang debian/libglx-mesa0/usr/lib/systemd/catalog \\\n'
     '\t\t--subject LOCAL1 --subject LOCAL3=LOCAL4\n'
     '  endif\n'),
]


def change(source, overlay, name, pairs):
    text = open(f'{source}/{name}', encoding='utf-8').read()
    if 'sparky-stereo-problems' in text:
        sys.exit(f'debian/{name} already names sparky-stereo-problems')
    for old, new in pairs:
        if text.count(old) != 1:
            sys.exit(f'debian/{name} is not the one this recipe knows: {old!r} is there {text.count(old)} times')
        text = text.replace(old, new)
    open(f'{overlay}/{name}', 'w', encoding='utf-8').write(text)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, overlay = sys.argv[1:]
    change(source, overlay, 'control', CONTROL)
    change(source, overlay, 'control.in', CONTROL)
    change(source, overlay, 'rules', RULES)


if __name__ == '__main__':
    main()
