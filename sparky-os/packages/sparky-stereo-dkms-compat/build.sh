#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(realpath -m "${1:?output directory required}")
PKG=sparky-stereo-dkms-compat
VERSION=0.1.0+lc1
umask 022
mkdir -p "$OUT"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
chmod 755 "$D"
install -Dm644 "$HERE/nvidia-fs-2.29.4.conf" "$D/etc/dkms/nvidia-fs-2.29.4.conf"
install -Dm644 "$HERE/patches/nvidia-fs-public-lock-header.patch" "$D/etc/dkms/nvidia-fs/patches/sparky-nvidia-fs-public-lock-header.patch"
install -Dm644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
mkdir -p "$D/DEBIAN"
cat > "$D/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Depends: dkms (>= 3.4.3)
Section: kernel
Priority: optional
Homepage: https://github.com/Sparky-OS/sparky-stereo-os
Description: Versioned DKMS compatibility fixes for Sparky Stereo kernels
 Preserve vendor package update paths while applying reviewed repairs to
 disposable module build copies. Includes the nvidia-fs 2.29.4 RT header fix.
CONTROL
printf '%s\n' /etc/dkms/nvidia-fs-2.29.4.conf /etc/dkms/nvidia-fs/patches/sparky-nvidia-fs-public-lock-header.patch > "$D/DEBIAN/conffiles"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
