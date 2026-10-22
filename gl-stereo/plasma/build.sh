#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" != 0
helper=${STEREO_DECLARE_SOURCE:?set by test-plasma.sh: the stereo-declare folder of plasma-wayland-protocols}
mkdir -p out/plasma/helper-source/stereo-declare out/plasma/helper-source/src/protocols
cp "$helper"/*.c "$helper"/*.h "$helper"/CMakeLists.txt "$helper"/*.in out/plasma/helper-source/stereo-declare/
cp "$helper/../src/protocols/kde-stereo-content-v1.xml" out/plasma/helper-source/src/protocols/
patch -d out/plasma/helper-source/stereo-declare -p1 < dependency-patches/stereo-declare-format-only.patch
patch -d out/plasma/helper-source/stereo-declare -p1 < plasma/stereo-declare-wayland-format.patch
cmake -S out/plasma/helper-source/stereo-declare -B out/plasma/helper-build -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/out/plasma/prefix" -DCMAKE_INSTALL_LIBDIR=lib
cmake --build out/plasma/helper-build -j4
cmake --install out/plasma/helper-build
cmake -S plasma -B out/plasma/build -G Ninja -DCMAKE_PREFIX_PATH="$PWD/out/plasma/prefix" -DCMAKE_BUILD_TYPE=Debug -DSAVER_DIRECTORY="$PWD/savers" -DSAVER_CATALOGUE="$PWD/out/eligibility/catalogue.json"
cmake --build out/plasma/build -j4
ctest --test-dir out/plasma/build --output-on-failure
