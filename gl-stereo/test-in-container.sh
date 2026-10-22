#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test "$(id -u)" != 0
mkdir -p out/home
trap 'if [ -n "${xpid:-}" ]; then kill "$xpid" 2>/dev/null || true; fi; rm -rf out/helper-source out/container-helper out/helper-install' EXIT
helper=${STEREO_DECLARE_SOURCE:?set by test.sh: the stereo-declare folder of plasma-wayland-protocols}
mkdir -p out/helper-source/stereo-declare out/helper-source/src/protocols
cp "$helper"/*.c "$helper"/*.h "$helper"/CMakeLists.txt "$helper"/*.in out/helper-source/stereo-declare/
cp "$helper/../src/protocols/kde-stereo-content-v1.xml" out/helper-source/src/protocols/
if ! grep -q 'int stereo_declare_x11_format(' out/helper-source/stereo-declare/stereo-declare.h; then
    patch -d out/helper-source/stereo-declare -p1 < dependency-patches/stereo-declare-format-only.patch
fi
cmake -S out/helper-source/stereo-declare -B out/container-helper -G Ninja -DCMAKE_INSTALL_PREFIX="$PWD/out/helper-install" -DCMAKE_INSTALL_LIBDIR=lib
cmake --build out/container-helper -j4
cmake --install out/container-helper
export PKG_CONFIG_PATH="$PWD/out/helper-install/lib/pkgconfig"
export LD_LIBRARY_PATH="$PWD/out/helper-install/lib"
export DISPLAY=:98 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=4
unset WAYLAND_DISPLAY LD_PRELOAD GL_STEREO
Xvfb :98 -screen 0 2560x1440x24 -ac -nolisten tcp > out/xvfb.txt 2>&1 &
xpid=$!
if [ "${GL_STEREO_TEST_SCOPE:-full}" = output ]; then
    sleep 1
    ./tests/run-output.sh
    gcc -shared -fPIC $(pkg-config --cflags stereo-declare) -o out/legacy-declaration.so \
        tests/legacy-declaration.c $(pkg-config --libs stereo-declare)
    ulimit -c 0
    rc=0
    env LD_PRELOAD="$PWD/libgl-stereo.so:$PWD/out/legacy-declaration.so" \
        GL_STEREO=1 TEST_SUPPORT_VERSION=2 ./tests/quad visual > out/old-helper-rejected.log 2>&1 || rc=$?
    test "$rc" = 134
    grep -q 'type == None' out/old-helper-rejected.log
    rm out/legacy-declaration.so
    echo 'PASS: legacy helper class-writing mutation rejected'
    exit
fi
for attempt in {1..50}; do
    if xdpyinfo >/dev/null 2>&1; then break; fi
    sleep .1
done
xdpyinfo >/dev/null
glxinfo -B > out/renderer.txt
if [ "${GL_STEREO_TEST_SCOPE:-full}" = savers ]; then
    ./tests/run-output.sh
    python3 tests/saver-frames.py
    python3 tests/starfield.py
    bash savers/build-rocks.sh
    python3 tests/rocks.py
    python3 tests/qualify-savers.py
    python3 tests/rotation.py
    python3 tests/display-pipe.py
    make install-savers DESTDIR="$PWD/out/install"
    exit
fi
./tests/run-all.sh
python3 tests/benchmark.py | tee out/benchmark.txt
