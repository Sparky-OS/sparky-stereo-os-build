#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# The configuration part of kernel/build-deb.sh: Debian's own configuration for the nearest kernel (linux-config-7.2 7.2.11-1),
# the edition's fragment on top (kernel/config/sparky-stereo.config, one reason above every option) and, for the v3 and rt
# flavours, the flavour's fragment; then make olddefconfig. Run from the kernel source root inside the build container.
#
#   configure.sh <flavour> [build-dir]          flavour: base | v3 | rt
#
# Without build-dir the configuration is written in the tree (.config), as the package build needs it. With build-dir (kbuild's
# O=) the tree is not written to, so tests can run it on a read-only mount without building anything.
set -eu
F=${1:?usage: configure.sh base|v3|rt [build-dir]}
B=${2:-.}
CFG=${CFG:-$(cd "$(dirname "$0")" && pwd)/config}
case "$F" in
    base|v3) BASE=$CFG/debian-7.2.11-amd64.config;;
    rt) BASE=$CFG/debian-7.2.11-rt-amd64.config;;
    *) echo "configure.sh: unknown flavour $F" >&2; exit 2;;
esac
FRAGS="$CFG/sparky-stereo.config"
[ -f "$CFG/flavour-$F.config" ] && FRAGS="$FRAGS $CFG/flavour-$F.config"
O=
[ "$B" = . ] || { mkdir -p "$B"; O="-O $B"; }
cp "$BASE" "$B/.config"
# shellcheck disable=SC2086
KCONFIG_CONFIG="$B/.config" scripts/kconfig/merge_config.sh -m $O "$B/.config" $FRAGS >"$B/merge-config.log" 2>&1
# shellcheck disable=SC2086
make -s ${O:+O="$B"} olddefconfig
# every option of the fragments must hold in the result, or the build is not the one that was asked for
python3 "$(dirname "$0")/tests/verify-fragment.py" "$B/.config" $FRAGS
