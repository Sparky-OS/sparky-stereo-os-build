#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
workspace=$(cd "$(dirname "$0")/../.." && pwd)
test -e /.dockerenv
test "$(id -u)" = 1000
build=/mnt/build/gl-stereo
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); the scripts that run apt in this root start with the helper
test -r /run/host-ca.crt && test -r /run/https-only-apt.sh
export PROOT_NO_SECCOMP=1
export LD_LIBRARY_PATH="$build/bootstrap/tools/usr/lib/x86_64-linux-gnu"
exec "${PROOT_BINARY:-$build/bootstrap/proot-5.4.0/src/proot}" -v "${PROOT_VERBOSE:-0}" -0 -r "${GL_STEREO_ROOTFS:-$build/rootfs}" \
    -b /dev -b /proc -b "$build:/build" -b /run/host-ca.crt -b /run/https-only-apt.sh \
    -b "$workspace:/workspace" \
    -b /var/local/sparky-stereo-repo:/var/local/sparky-stereo-repo \
    -w /build /usr/bin/env -u LD_LIBRARY_PATH HOME=/build/home LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive \
    DEB_BUILD_OPTIONS=parallel=4 CMAKE_BUILD_PARALLEL_LEVEL=4 "$@"
