#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
"""ORDER 574: the Wayland client tells the person through the problems engine (sparky-stereo-problems) when a window
that asked for two views was given one. From the +21 source's debian folder, write into the overlay: control with
the engine as a build dependency and as a dependency of libqt6waylandclient6 (amd64, where the engine is built);
libqt6gui6 breaking a Vulkan stereo layer older than Mesa +stereo3d24 (o574-0003); rules with the engine's library path for CMake and the package's catalogs made in the amd64 build; the package's
postrm that ends its problems when it is removed. Usage: debian-stereo3d22.py PREVIOUS_DEBIAN OVERLAY"""
from pathlib import Path
import sys
source, out = map(Path, sys.argv[1:])

def replace_once(s, a, b):
    if s.count(a) != 1:
        raise SystemExit(f'expected one packaging anchor: {a!r}')
    return s.replace(a, b)

engine = 'sparky-stereo-problems (>= 0.1.2) [amd64]'
s = (source / 'control').read_text()
s = replace_once(s, '               dh-exec,\n', f'               dh-exec,\n               {engine},\n')
a = s.index('Package: libqt6waylandclient6\n')
b = s.index('\n\n', a)
before, p, after = s[:a], s[a:b], s[b:]
p = replace_once(p, 'Depends: ${misc:Depends},\n         ${shlibs:Depends},\n',
                 f'Depends: ${{misc:Depends}},\n         ${{shlibs:Depends}},\n         {engine},\n')
s = before + p + after
# Qt's own Vulkan swapchain no longer makes the surface again when a window drops to one view (o574-0003): the
# Vulkan stereo layer withdraws its declaration with the pair from Mesa +stereo3d24 on (ORDER 573), and with an
# older layer such a window is shown as two halves
a = s.index('Package: libqt6gui6\n')
b = s.index('\n\n', a)
before, p, after = s[:a], s[a:b], s[b:]
p = replace_once(p, 'Breaks: libqt6gui6t64 (<< ${source:Version}),\n',
                 'Breaks: libqt6gui6t64 (<< ${source:Version}),\n'
                 '        mesa-vulkan-layer-stereo (<< 26.1.6-1+stereo3d24~),\n')
(out / 'control').write_text(before + p + after)

s = (source / 'rules').read_text()
s = replace_once(s, '\t\t-DCMAKE_INSTALL_PREFIX=/usr \\\n',
                 '\t\t-DCMAKE_INSTALL_PREFIX=/usr \\\n'
                 '\t\t-DQT_SPARKY_STEREO_PROBLEMS_LIBRARY=/usr/lib/$(DEB_HOST_MULTIARCH)/sparky-stereo-problems/libsparky-stereo-problems.so.0 \\\n')
if 'execute_after_dh_install' in s:
    raise SystemExit('rules already has an execute_after_dh_install target: merge the catalog step into it')
s = replace_once(s, 'override_dh_makeshlibs:\n',
                 '# The messages of the problem the Wayland client keeps (a window that asked for two views and was given one,\n'
                 '# ORDER 574), as journal catalogs from debian/lang in the ten languages; the engine is an amd64 package.\n'
                 'execute_after_dh_install-arch:\n'
                 'ifeq ($(DEB_HOST_ARCH), amd64)\n'
                 '\tinstall -m755 -d debian/libqt6waylandclient6/usr/lib/systemd/catalog\n'
                 '\tsparky-stereo-problems catalog libqt6waylandclient6 debian/lang debian/libqt6waylandclient6/usr/lib/systemd/catalog --subject LOCAL1\n'
                 'endif\n\n'
                 'override_dh_makeshlibs:\n')
(out / 'rules').write_text(s)

(out / 'libqt6waylandclient6.postrm').write_text('''#!/bin/sh
set -e
if { [ "$1" = remove ] || [ "$1" = purge ]; } && command -v sparky-stereo-problems >/dev/null 2>&1; then
    sparky-stereo-problems clear --all libqt6waylandclient6 ||
        echo "libqt6waylandclient6: its kept problems could not be ended" >&2
fi
#DEBHELPER#
exit 0
''')
