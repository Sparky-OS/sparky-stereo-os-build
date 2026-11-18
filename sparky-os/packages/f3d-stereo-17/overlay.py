#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
"""Sparky Stereo OS, ORDER 17: the changes to Debian's own debian/ of f3d 3.5.0+dfsg-3 that make libf3d shared (libf3d3,
libf3d-dev), draw a model as a stereo pair for the file manager, and enable 3D by default.
Run in the unpacked source: overlay.py DEBIAN_ADD_DIR
Every replace states what it expects and stops when Debian's file is not the one this was written for."""
import re
import sys
from pathlib import Path

add = Path(sys.argv[1])
rules = Path('debian/rules').read_text()
assert '-DBUILD_SHARED_LIBS=OFF' in rules and 'override_dh_auto_install:' in rules, 'Debian rules changed'
rules = rules.replace('-DBUILD_SHARED_LIBS=OFF', '-DBUILD_SHARED_LIBS=ON -DF3D_WITH_STEREO_DECLARE=ON')
rules = rules[:rules.index('override_dh_auto_install:')]
rules = rules.replace('%:\n\tdh $@', 'include /usr/share/dpkg/architecture.mk\n\n%:\n\tdh $@', 1)
rules += (
    "override_dh_auto_install:\n"
    "\t# Install configuration files first and change the folder path to /etc/f3d instead of /share/f3d.\n"
    "\tcmake --install obj-$(DEB_BUILD_GNU_TYPE) --prefix=debian/f3d --component configuration\n"
    "\tmkdir -p debian/f3d/etc/f3d\n"
    "\tmv debian/f3d/share/f3d/configs debian/f3d/etc/f3d/configs\n"
    "\trm -r debian/f3d/share\n"
    "\t# F3D reads /etc/f3d/config.json and /etc/f3d/config.d (the log of --verbose=debug lists the candidates); Debian's own\n"
    "\t# /etc/f3d/configs is looked in by nobody, so the default of this edition goes where F3D looks\n"
    "\tinstall -D -m 644 debian/50_sparky_stereo.json debian/f3d/etc/f3d/config.d/50_sparky_stereo.json\n"
    "\tdh_auto_install --destdir=debian/tmp\n"
    "\t# The SDK (headers, CMake files) is not in the default components.\n"
    "\tcmake --install obj-$(DEB_BUILD_GNU_TYPE) --prefix=debian/tmp/usr --component sdk\n"
    "\trm -r debian/tmp/usr/share/doc\n"
    "\t# libvtkext is private to libf3d (no soname, no other user): it goes in a folder of the package, and libf3d looks there\n"
    "\tmkdir -p debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/f3d\n"
    "\tmv debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/libvtkext.so debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/f3d/\n"
    "\tpatchelf --set-rpath /usr/lib/$(DEB_HOST_MULTIARCH)/f3d debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/libf3d.so.3.5\n"
    "\t# The thumbnailer that draws a model as a stereo pair (two parallel cameras) through libf3d\n"
    "\tg++ $(CXXFLAGS) $(CPPFLAGS) -std=c++17 debian/f3d-thumbnail-pair.cxx -Idebian/tmp/usr/include "
    "-Ldebian/tmp/usr/lib/$(DEB_HOST_MULTIARCH) -lf3d -lz $(LDFLAGS) -Wl,-rpath-link,debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/f3d "
    "-o debian/tmp/usr/bin/f3d-thumbnail-pair\n"
    "\tfor t in debian/tmp/usr/share/thumbnailers/*.thumbnailer; do \\\n"
    "\t\tplugin=$$(sed -n 's/.*--load-plugins=\\([a-z0-9]*\\).*/\\1/p' $$t); \\\n"
    "\t\tsed -i \"s|^Exec=.*|Exec=f3d-thumbnail-pair $$plugin %s %i %o|; s|^TryExec=.*|TryExec=f3d-thumbnail-pair|\" $$t; \\\n"
    "\tdone\n"
    "\t# KIO matches a thumbnailer to the name of a file's type, never to its aliases: name each type\n"
    "\tfor t in debian/tmp/usr/share/thumbnailers/*.thumbnailer; do \\\n"
    "\t\tsed -i -e 's|application/vnd.ply|model/x-ply;application/vnd.ply|; s|application/vnd.splat|model/x-gaussian-splat;application/vnd.splat|; "
    "s|application/vnd.spz|model/x-spz;application/vnd.spz|; s|application/vnd.pts|model/x-pts;application/vnd.pts|; "
    "s|application/vnd.fbx|model/x-fbx;application/vnd.fbx|; s|application/vnd.dae|model/vnd.collada+xml;application/vnd.dae|; "
    "s|application/vnd.off|model/x-off;application/vnd.off|; s|application/vnd.drc|model/x-draco;application/vnd.drc|; "
    "s|application/vnd.step|model/step;application/vnd.step|; s|application/vnd.brep|model/x-brep;application/vnd.brep|' $$t; \\\n"
    "\tdone\n"
    "\n"
    "# patchelf leaves a section after the debug sections of libf3d, which dwz refuses: libf3d keeps its debug sections as they are\n"
    "override_dh_dwz:\n"
    "\tdh_dwz -Xlibf3d.so.3.5\n"
    "\n"
    "override_dh_shlibdeps:\n"
    "\tdh_shlibdeps -l$(CURDIR)/debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/f3d\n"
    "\n"
    "override_dh_missing:\n"
    "\tdh_missing --fail-missing\n"
)
Path('debian/rules').write_text(rules)

control = Path('debian/control').read_text()
old = 'Package: f3d\nArchitecture: any\nDepends: ${shlibs:Depends}, ${misc:Depends}'
assert old in control, 'Debian control changed'
control = control.replace(old, 'Package: f3d\nArchitecture: any\n'
                          'Depends: libf3d3 (= ${binary:Version}), sparky-stereo-mime-models, ${shlibs:Depends}, ${misc:Depends}', 1)
control = control.replace('Build-Depends: debhelper-compat (= 13),', 'Build-Depends: debhelper-compat (= 13),\n               libstereo-declare-dev (>= 1.10.0),\n               patchelf,\n               zlib1g-dev,', 1)
control += """
Package: libf3d3
Section: libs
Architecture: any
Multi-Arch: same
Depends: ${shlibs:Depends}, ${misc:Depends}
Description: F3D library: load and render 3D files, with stereo
 libf3d is the library under F3D: readers for glTF, STL, PLY, OBJ, STEP,
 splats and more, and a renderer that draws into its own window, an
 external OpenGL context or an image. Sparky Stereo OS builds it with the
 render.stereo option, which draws the two eyes of a stereo window or of an
 image.

Package: libf3d-dev
Section: libdevel
Architecture: any
Multi-Arch: same
Depends: libf3d3 (= ${binary:Version}), ${misc:Depends}
Description: F3D library: headers and CMake files
 Development files for libf3d, the library under F3D.
"""
Path('debian/control').write_text(control)
Path('debian/f3d.install').write_text('usr/bin\nusr/share\n')
Path('debian/f3d.manpages').write_text('debian/f3d-thumbnail-pair.1\n')
Path('debian/libf3d3.install').write_text('usr/lib/*/libf3d.so.*\nusr/lib/*/f3d/libvtkext.so\n')
Path('debian/libf3d-dev.install').write_text('usr/include\nusr/lib/*/libf3d.so\nusr/lib/*/cmake\n')
for name in ('f3d-thumbnail-pair.cxx', '50_sparky_stereo.json', 'f3d-thumbnail-pair.1'):
    Path('debian', name).write_text((add / name).read_text())
