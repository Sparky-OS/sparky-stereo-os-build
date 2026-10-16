#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
source=${1:?source checkout}
cd /build/installed-tests
mkdir -p out/window-sizing
cp "$source"/tests/{run-window-rig,check-window-rig}.py tests/
cp out/window-sizing-client out/window-sizing/client
# This source build is solely the deliberate old-behaviour negative control.
sed 's/w->compositor_sizes = support >= 3;/w->compositor_sizes = 0;/' "$source/gl-stereo.c" >out/window-sizing/legacy-sizing.c
gcc -fPIC -O2 -fvisibility=hidden -pthread -shared -Wl,--no-undefined -I"$source" \
    $(pkg-config --cflags stereo-declare) out/window-sizing/legacy-sizing.c \
    -o out/window-sizing/before.so -ldl -lGL -lX11 -lwayland-client -lm -pthread $(pkg-config --libs stereo-declare)
test "$(readlink -f libgl-stereo.so)" = /usr/lib/gl-stereo/libgl-stereo.so
for name in before after quad future gears; do
    python3 tests/run-window-rig.py "$name" >"out/window-sizing/$name.log" 2>&1
done
python3 tests/check-window-rig.py
