#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Packaging smoke test of kernel/build-deb.sh: builds a tiny kernel (tests/smoke.fragment) through the same container, bindeb-pkg, module signing, BTF,
# headers repack and checks as a real build, without the patch series and without Debian's configuration. Takes about ten minutes; run it after any change
# to build-deb.sh or build-inner.sh, before a build that takes hours.
#
#   kernel/tests/package-smoke.sh [out-dir]       (default /K3D/temp/linux-stereo3d-smoke; WORK, CPUS, JOBS, KERNEL_GIT as for build-deb.sh)
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-/K3D/temp/linux-stereo3d-smoke}
export WORK=${WORK:-/K3D/temp/linux-stereo3d-smoke-build}
exec "$HERE/build-deb.sh" -b 0 -t -o "$OUT"
