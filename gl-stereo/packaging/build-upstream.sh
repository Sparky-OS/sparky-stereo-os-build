#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
case "$1" in
    xscreensaver) tree=xscreensaver-6.09+dfsg1 ;;
    kscreenlocker) tree=kscreenlocker-6.7.4 ;;
    plasma-desktop) tree=plasma-desktop-6.7.4 ;;
    *) exit 2 ;;
esac
cd "/build/sources/$tree"
export DEB_BUILD_OPTIONS=parallel=4
export CMAKE_BUILD_PARALLEL_LEVEL=4
dpkg-buildpackage -us -uc -sa -j4
