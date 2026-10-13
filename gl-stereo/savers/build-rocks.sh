#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test "$(id -u)" != 0
repo=$PWD
trap 'rm -rf "$repo/out/rocks-source" "$repo/out/xscreensaver.tar.xz" "$repo/out/x11-frame.o"' EXIT
rm -rf out/rocks-source
mkdir -p out/rocks-source out/bin
if [ ! -f out/xscreensaver.tar.xz ]; then
    curl -fsSL https://deb.debian.org/debian/pool/main/x/xscreensaver/xscreensaver_6.09+dfsg1.orig.tar.xz -o out/xscreensaver.tar.xz
fi
echo '678cbcbe8e15cc5789c9a9cec8e5419a001668dd7cbb884c11ca7ffe9ff4600e  out/xscreensaver.tar.xz' | sha256sum -c -
tar -xf out/xscreensaver.tar.xz -C out/rocks-source --strip-components=1
patch -d out/rocks-source -p1 < savers/rocks-sbs.patch
cp savers/saver-x11-frame.h out/rocks-source/hacks/
gcc -O2 -Wall -Wextra -fPIC -c savers/x11-frame.c -o out/x11-frame.o
cd out/rocks-source
# Only the rocks hack is built, never the XScreenSaver locker or daemon.
./configure --without-gtk --without-pam --without-login-manager --without-systemd > ../rocks-configure.log 2>&1 || {
    # Upstream returns 1 for the deliberately omitted locker/settings features.
    test -f hacks/Makefile && test -f utils/Makefile
    ! grep -Ei '(^error:|configure: error:|it is required)' ../rocks-configure.log
}
make -C utils -j4 xmu.o > ../rocks-build.log 2>&1
make -C hacks -j4 rocks CPPFLAGS="$(pkg-config --cflags stereo-declare)" \
    LIBS="$repo/out/x11-frame.o $(pkg-config --libs stereo-declare)" >> ../rocks-build.log 2>&1
cp hacks/rocks ../bin/rocks
