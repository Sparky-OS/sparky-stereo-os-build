#!/bin/sh
# The configuration part of kernel/build-deb.sh: the running Debian kernel's whole
# configuration with the overrides below, then make olddefconfig. Run from the kernel source
# root inside the build container.
#
#   configure.sh <base.config> [build-dir]
#
# Without build-dir the configuration is written in the tree (.config), as the package build
# needs. With build-dir (kbuild's O=) the tree is not written to, so tests can run it on a
# read-only mount and look at the result without building anything.
set -eu
BASE=$1
B=${2:-.}
O=
[ "$B" = . ] || { mkdir -p "$B"; O="O=$B"; }
cp "$BASE" "$B/.config"
# Signing keys: a rebuild outside Debian has not Debian's. Debug information: DWARF at the
# toolchain's default, as Debian has it, because BTF (which sched_ext needs) is made from
# it by pahole; DEBUG_INFO_REDUCED and DEBUG_INFO_SPLIT would forbid BTF. SCHED_CLASS_EXT
# (the scx schedulers) depends on BPF_SYSCALL, BPF_JIT and DEBUG_INFO_BTF. The four Realtek
# drivers are in the tree and off in Debian's configuration. VKMS (virtual KMS) is a module,
# loaded only where needed: KWin's DRM tests open it as /dev/dri/card1 (Daniel, 2026-10-06).
scripts/config --file "$B/.config" --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
  --enable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_BTF --enable SCHED_CLASS_EXT \
  --disable MODULE_SIG_ALL --module DRM_NOUVEAU --module DRM_AMDGPU \
  --module RTW89_8852AU --module RTW89_8852CU --module RTW89_8922AU --module RTW89_8922DE --module DRM_VKMS
# shellcheck disable=SC2086
make -s $O olddefconfig
