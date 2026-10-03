#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y install --no-install-recommends build-essential pkg-config cmake ninja-build \
    libgl-dev libegl-dev libx11-dev libwayland-dev wayland-protocols \
    xvfb xauth x11-utils mesa-utils xscreensaver-gl xscreensaver-gl-extra \
    python3-pil python3-numpy python3-tk paraview python3-paraview
mkdir -p out
helper=${STEREO_DECLARE_SOURCE:-/K3D/GitHub/sparky-stereo-os-build/plasma-wayland-protocols/stereo-declare}
cmake -S "$helper" -B out/container-helper -G Ninja -DCMAKE_INSTALL_PREFIX=/opt/stereo-declare
cmake --build out/container-helper -j4
cmake --install out/container-helper
export PKG_CONFIG_PATH=/opt/stereo-declare/lib/pkgconfig
export LD_LIBRARY_PATH=/opt/stereo-declare/lib
export DISPLAY=:98 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=4
unset WAYLAND_DISPLAY LD_PRELOAD GL_STEREO
Xvfb :98 -screen 0 2560x1440x24 -ac -nolisten tcp > out/xvfb.txt 2>&1 &
xpid=$!
trap 'kill "$xpid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do
    if xdpyinfo >/dev/null 2>&1; then break; fi
    sleep .1
done
xdpyinfo >/dev/null
glxinfo -B > out/renderer.txt
./tests/run-all.sh
python3 tests/benchmark.py | tee out/benchmark.txt
