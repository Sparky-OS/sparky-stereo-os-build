#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# test-element-limit.sh BUILDER_WITH_BUILD_DEPENDENCIES BUILD_DIRECTORY RESULTS
# Reuse build-70.sh's object directory; only the integration test target is built.
set -euo pipefail
image=$1 work=$(realpath "$2") out=$(mkdir -p "$3" && cd "$3" && pwd -P)
name=${BUILD_NAME_PREFIX:?use the lane prefix}-element-test
test -f "$work/lc/source/obj-x86_64-linux-gnu/CMakeCache.txt"
launch_status=0
docker run --name "$name" --pull=never --platform linux/amd64 --network none --ulimit core=1 --cpus 4 \
    --mount "type=bind,src=$work,dst=/work" --mount "type=bind,src=$out,dst=/out" \
    "$image" bash -ec '
    unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
    export LANG=C.UTF-8 QT_QPA_PLATFORM=offscreen EGL_PLATFORM=surfaceless
    export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
    XDG_RUNTIME_DIR=$(mktemp -d)
    export XDG_RUNTIME_DIR
    trap "rm -rf \"$XDG_RUNTIME_DIR\"; chown -R 1000:1000 /out /work" EXIT
    chown 1000:1000 "$XDG_RUNTIME_DIR"
    args=(setpriv --reuid=1000 --regid=1000 --clear-groups env HOME="$XDG_RUNTIME_DIR")
    src=/work/lc/source
    obj=$src/obj-x86_64-linux-gnu
    "${args[@]}" cmake -S "$src" -B "$obj" -DBUILD_TESTING=ON > /out/configure.log 2>&1
    "${args[@]}" cmake --build "$obj" -j4 --target testStereoDepthExchange > /out/build.log 2>&1
    "${args[@]}" dbus-run-session -- timeout 300 "$obj/bin/testStereoDepthExchange" > /out/test.log 2>&1
' || launch_status=$?
docker inspect -f '{{.Id}}' "$name" >> "${CIDS:-/dev/null}"
docker rm "$name" > /dev/null
exit "$launch_status"
