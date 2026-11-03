#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-cuda-repo: NVIDIA's CUDA repository for Sparky Stereo OS, with the edition's pins. NVIDIA's
# repository may update compute (CUDA), never the display driver, which is the edition's, with HDMI 3D (Daniel,
# 2026-10-11), and NVIDIA's rebuilds of Debian's own tools do not replace Debian's (ORDER 338). It installs
#   /usr/share/sparky-stereo-cuda-repo/sparky-stereo-cuda.sources   (deb822: the flat repository for Debian 13, amd64
#                                                      and i386, Signed-By NVIDIA's key), which the postinst writes to
#                                                      /etc/apt/sources.list.d only when no other source names the
#                                                      repository, and the postrm removes
#   /usr/share/keyrings/cuda-archive-keyring.gpg         (NVIDIA's key, byte for byte the file NVIDIA's cuda-keyring 1.1-1
#                                                      installs there; cuda-key.sh holds its checksums)
#   /etc/apt/preferences.d/91sparky-stereo-cuda           (the pins: CUDA at 1002, NVIDIA's EGL platform libraries at 1002,
#                                                      the rest of the repository at 100)
# The image and the hardware setup wrote the source and the pin themselves before this package (iso-build/apt-setup.sh,
# sparky-stereo-hardware up to 0.1.14); the package now owns them, and its preinst takes over the files nobody changed.
# The pin is a conffile (Debian Policy 10.7.3: "local changes must be preserved during a package upgrade"). The source is
# the other kind Policy names, a file the maintainer scripts manage: a conffile cannot be left out, and a source of the
# person's own for the same URI must be kept, since two sources for one URI with different Signed-By stop apt.
# It depends on sparky-stereo-nvidia-driver-lock, so NVIDIA's repository never comes without the lock that keeps NVIDIA's
# driver at the version of the edition's module. It replaces NVIDIA's cuda-keyring's key file (Debian Policy 7.6.1): both
# install the same bytes there, and cuda-keyring stays installed; its source is a source of the person's own.
# Needs dpkg-deb and python3. Usage: OUT=DIR build.sh   (output goes to $OUT, default the current folder)
# Last update 2026/11/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$PWD}
VERSION=${VERSION:-20261103.1~sparky9~0+lc1}
PKG=sparky-stereo-cuda-repo
# shellcheck source=cuda-key.sh
. "$HERE/cuda-key.sh"
got=$(sha256sum <"$HERE/cuda-archive-keyring.gpg" | cut -d' ' -f1)
[ "$got" = "$CUDA_KEYRING_SHA256" ] || { echo "build: cuda-archive-keyring.gpg is $got, not NVIDIA's $CUDA_KEYRING_SHA256" >&2; exit 1; }
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
D=$W/$PKG
install -Dm644 "$HERE/sparky-stereo-cuda.sources" "$D/usr/share/$PKG/sparky-stereo-cuda.sources"
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
Replaces: cuda-keyring
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: NVIDIA's CUDA repository for Sparky Stereo OS
  The apt source and key of NVIDIA's CUDA repository for Debian 13 (amd64,
  and i386 for NVIDIA's driver libraries that 32-bit programs need), with
  the edition's pins: CUDA and NVIDIA's other compute libraries update
  from it, NVIDIA's driver stays at the version of the edition's stereo 3D
  module (sparky-stereo-nvidia-driver-lock), and NVIDIA's builds of Debian's
  own tools, such as dkms, do not replace the edition's or Debian's. A source
  of your own for the same repository is kept, with these pins. Remove it to
  remove the repository.
EOF
printf '%s\n' /etc/apt/preferences.d/91sparky-stereo-cuda >"$D/DEBIAN/conffiles"
install -m755 "$HERE/debian-scripts/preinst" "$HERE/debian-scripts/postinst" "$D/DEBIAN/"
# postrm runs when the template is already gone, so it compares the written source with the template's checksum
sed "s/@TEMPLATE_MD5@/$(md5sum <"$HERE/sparky-stereo-cuda.sources" | cut -d' ' -f1)/g" "$HERE/debian-scripts/postrm" >"$D/DEBIAN/postrm"
chmod 755 "$D/DEBIAN/postrm"
if grep -q '@TEMPLATE_MD5@' "$D/DEBIAN/postrm"; then echo 'build: the postrm still has its placeholder' >&2; exit 1; fi
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
