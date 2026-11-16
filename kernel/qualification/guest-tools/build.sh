#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# build.sh SOURCE_DIR VMLINUX_BTF OUT_DIR: makes the tools the qualification guest is given with --guest-dir
# (qualify-kernel-unsigned.py and qualify-kernel-boot.py copy it as inputs/guest): OUT_DIR/bin/scx_simple, built from the
# kernel tree's own tools/sched_ext (with the tree's own bpftool and libbpf), and OUT_DIR/lib with the dynamic loader and
# every library scx_simple loads, as features.sh runs it: $LD --library-path /guest/lib /guest/bin/scx_simple.
# VMLINUX_BTF is any vmlinux with BTF of the same release line, such as the BTF-only vmlinux a linux-headers package ships;
# the scheduler is CO-RE, so it loads on the kernel being qualified.
# Run it in a container that has make, gcc, clang, llvm, libelf-dev, zlib1g-dev, libzstd-dev and pkg-config, as an ordinary
# user; SOURCE_DIR may be read-only (the build goes to OUT_DIR/build).
# Until ORDER 627 this folder was a fixture of the kernel-soul lane (bench-run/r2/initrd-tree/guest), removed with that lane.
set -eu
SRC=${1:?usage: build.sh SOURCE_DIR VMLINUX_BTF OUT_DIR}
BTF=${2:?usage: build.sh SOURCE_DIR VMLINUX_BTF OUT_DIR}
OUT=${3:?usage: build.sh SOURCE_DIR VMLINUX_BTF OUT_DIR}
[ -d "$SRC/tools/sched_ext" ] || { echo "build.sh: $SRC has no tools/sched_ext" >&2; exit 1; }
[ -r "$BTF" ] || { echo "build.sh: cannot read $BTF" >&2; exit 1; }
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/build"
make -C "$SRC/tools/sched_ext" O="$OUT/build" VMLINUX_BTF="$BTF" -j"$(nproc)" scx_simple
cp "$OUT/build/build/bin/scx_simple" "$OUT/bin/scx_simple"
ldd "$OUT/bin/scx_simple" | awk '/=> \// { print $3 } /^[[:space:]]*\/.*ld-linux/ { print $1 }' | while read -r lib; do
    cp -L "$lib" "$OUT/lib/"
done
[ -e "$OUT/lib/ld-linux-x86-64.so.2" ] || { echo "build.sh: the dynamic loader was not found by ldd" >&2; exit 1; }
rm -rf "$OUT/build"
"$OUT/lib/ld-linux-x86-64.so.2" --library-path "$OUT/lib" "$OUT/bin/scx_simple" -h > /dev/null 2>&1 || true
ls -l "$OUT/bin" "$OUT/lib"
