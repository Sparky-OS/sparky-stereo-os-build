#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# build-test-kernel.sh SRC_DIR OUT_DIR [FRAGMENT...]
#
# Builds a small kernel that is enough for the bench: `make tinyconfig`, plus kconfig/bench-x86_64.fragment, plus any extra
# fragments (files of CONFIG_ lines), then bzImage and `modules` (which makes Module.symvers for the test module). SRC_DIR is an
# unpacked Linux source tree and is not written to; the build goes to OUT_DIR (kbuild's O=). It takes a few minutes. Needs gcc, make, bc,
# bison, flex, libssl-dev, libelf-dev (the Docker image has them).
set -eu
SRC=$(cd "${1:?usage: build-test-kernel.sh SRC_DIR OUT_DIR [FRAGMENT...]}" && pwd)
OUT=${2:?out dir}
shift 2
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
cd "$SRC"
make O="$OUT" tinyconfig >/dev/null
KCONFIG_CONFIG="$OUT/.config" scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "$HERE/kconfig/bench-x86_64.fragment" "$@" >"$OUT/merge.log" 2>&1
make O="$OUT" olddefconfig >/dev/null
make O="$OUT" -j"${JOBS:-$(nproc)}" bzImage modules
echo "kernel: $OUT/arch/x86/boot/bzImage    build tree for --ksrc: $OUT"
