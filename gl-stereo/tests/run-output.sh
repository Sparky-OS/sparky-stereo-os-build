#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
make clean
make -j4
mkdir -p out/window-sizing
sed 's/w->compositor_sizes = support >= 3;/w->compositor_sizes = 0;/' gl-stereo.c >out/window-sizing/legacy-sizing.c
gcc -fPIC -O2 -fvisibility=hidden -pthread -shared -Wl,--no-undefined -I. \
    $(pkg-config --cflags stereo-declare) out/window-sizing/legacy-sizing.c \
    -o out/window-sizing/before.so -ldl -lGL -lX11 -lm -pthread $(pkg-config --libs stereo-declare)
rm out/window-sizing/legacy-sizing.c
gcc -O2 -Wall -Wextra tests/window-sizing.c -o out/window-sizing-client -lGL -lX11 -ldl
for version in 0 1 2; do
    env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 TEST_SUPPORT_VERSION="$version" ./out/window-sizing-client
done
mkdir -p out/synthetic out/egl-damage
./run-synthetic-tests.sh
env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 ./tests/state
env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 ./tests/egl-damage
for profile in none game scientific unknown; do
    for mode in visual fbconfig auto; do
        env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 GL_STEREO_CLASS="$profile" ./tests/quad "$mode"
        env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 GL_STEREO_CLASS="$profile" TEST_PRESET_CLASS=1 ./tests/quad "$mode"
    done
done
env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 ./tests/quad unsupported
env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 GL_STEREO_RENDER_RESOLUTION=400x240 ./tests/quad
make install DESTDIR="$PWD/out/install"
echo 'PASS: output contract, preserved inputs and staged install'
