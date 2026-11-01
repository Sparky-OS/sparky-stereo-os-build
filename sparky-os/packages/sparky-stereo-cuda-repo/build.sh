#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-cuda-repo: NVIDIA's CUDA repository for Sparky Stereo OS, with the edition's pins. NVIDIA's
# repository may update compute (CUDA), never the display driver, which is the edition's, with HDMI 3D (Daniel,
# 2026-10-11), and NVIDIA's rebuilds of Debian's own tools do not replace Debian's (ORDER 338). It installs
#   /etc/apt/sources.list.d/sparky-stereo-cuda.sources   (deb822: the flat repository for Debian 13, amd64 only,
#                                                      Signed-By NVIDIA's key)
#   /usr/share/keyrings/cuda-archive-keyring.gpg         (NVIDIA's key, byte for byte the file NVIDIA's cuda-keyring 1.1-1
#                                                      installs there; cuda-key.sh holds its checksums)
#   /etc/apt/preferences.d/91sparky-stereo-cuda           (the pins: CUDA at 1002, NVIDIA's EGL platform libraries at 1002,
#                                                      the rest of the repository at 100)
# The image and the hardware setup wrote the source and the pin themselves before this package (iso-build/apt-setup.sh,
# sparky-stereo-hardware up to 0.1.14); the package now owns them, and its preinst takes over the files nobody changed.
# Both /etc files are conffiles (Debian Policy 10.7.3: "local changes must be preserved during a package upgrade").
# It depends on sparky-stereo-nvidia-driver-lock, so NVIDIA's repository never comes without the lock that keeps NVIDIA's
# driver at the version of the edition's module. It conflicts with and replaces NVIDIA's cuda-keyring (Debian Policy
# 7.6.2): both install the same key file, and a cuda-keyring source left behind names the same key as this one, which apt
# accepts (two sources for one URI with different Signed-By stop apt).
# Needs dpkg-deb and python3. Usage: OUT=DIR build.sh   (output goes to $OUT, default the current folder)
# Last update 2026/11/01
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$PWD}
VERSION=${VERSION:-20261101.1~sparky9~0+lc1}
PKG=sparky-stereo-cuda-repo
# shellcheck source=cuda-key.sh
. "$HERE/cuda-key.sh"
got=$(sha256sum <"$HERE/cuda-archive-keyring.gpg" | cut -d' ' -f1)
[ "$got" = "$CUDA_KEYRING_SHA256" ] || { echo "build: cuda-archive-keyring.gpg is $got, not NVIDIA's $CUDA_KEYRING_SHA256" >&2; exit 1; }
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
D=$W/$PKG
install -Dm644 "$HERE/sparky-stereo-cuda.sources" "$D/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
install -Dm644 "$HERE/91sparky-stereo-cuda" "$D/etc/apt/preferences.d/91sparky-stereo-cuda"
install -Dm644 "$HERE/cuda-archive-keyring.gpg" "$D/usr/share/keyrings/cuda-archive-keyring.gpg"
install -Dm644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
mkdir -p "$D/DEBIAN"
find "$D" -type d -exec chmod 755 {} +
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: apt, sparky-stereo-nvidia-driver-lock
Conflicts: cuda-keyring
Replaces: cuda-keyring
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: NVIDIA's CUDA repository for Sparky Stereo OS
  The apt source and key of NVIDIA's CUDA repository for Debian 13 (amd64),
  with the edition's pins: CUDA and NVIDIA's other compute libraries update
  from it, NVIDIA's driver stays at the version of the edition's stereo 3D
  module (sparky-stereo-nvidia-driver-lock), and NVIDIA's builds of Debian's
  own tools, such as dkms, do not replace Debian's. Purge it to remove the
  repository.
EOF
printf '%s\n' /etc/apt/sources.list.d/sparky-stereo-cuda.sources /etc/apt/preferences.d/91sparky-stereo-cuda >"$D/DEBIAN/conffiles"
install -m755 "$HERE/debian-scripts/preinst" "$HERE/debian-scripts/postinst" "$HERE/debian-scripts/postrm" "$D/DEBIAN/"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
