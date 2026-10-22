#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
test -e /.dockerenv
test "$(id -u)" = 1000
build=/mnt/build/gl-stereo/bootstrap
# Download the verified Debian proot source and libtalloc-dev with the
# original bootstrap proot before running this compiler-container step.
cd "$build"
if [ ! -d proot-5.4.0 ]; then
    dpkg-source --no-check -x proot_5.4.0-3.dsc
    patch -d proot-5.4.0 -p1 < "$here/proot-empty-path.patch"
fi
for deb in tools/libtalloc-dev*.deb; do dpkg-deb -x "$deb" tools; done
export PKG_CONFIG_PATH="$build/tools/usr/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$build/tools"
make -C proot-5.4.0/src -j4 HAS_SWIG= HAS_PYTHON_CONFIG=
