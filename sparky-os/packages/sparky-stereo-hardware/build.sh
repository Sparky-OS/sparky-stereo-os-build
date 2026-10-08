#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.3
PACKAGE=sparky-stereo-hardware
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.sparky-stereo-hardware.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/sparky-stereo-hardware
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/sparky-stereo-hardware"
install -m644 "$HERE/copyright" "$D/usr/share/doc/sparky-stereo-hardware/copyright"
source "$HERE/payload.sh"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: sparky-stereo-hardware
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: apt, bash, ca-certificates, coreutils, curl, grep, isenkram-cli, kmod, laptop-detect, lm-sensors, nvidia-detect, pciutils, power-profiles-daemon (>= 0.30), python3, sed, sparky-remsu, sparky-xterm, udev, usbutils, util-linux, yad
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Detect and configure matched hardware for Sparky Stereo OS
  Hardware support selected by sparky-stereo-hardware after detection.
EOF
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_all.deb"
S=$W/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<EOF
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: dpkg-dev
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: all
Depends: apt, bash, ca-certificates, coreutils, curl, grep, isenkram-cli, kmod, laptop-detect, lm-sensors, nvidia-detect, pciutils, power-profiles-daemon (>= 0.30), python3, sed, sparky-remsu, sparky-xterm, udev, usbutils, util-linux, yad
Description: Detect and configure matched hardware for Sparky Stereo OS
 Hardware support selected after detection.
EOF
cat >"$S/debian/changelog" <<EOF
$PACKAGE ($VERSION) unstable; urgency=medium

  * Enable matched PPD AMD actions and NVIDIA laptop runtime power management.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 08 Oct 2026 12:15:00 -0300
EOF
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOF'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_all.deb System optional
clean:
build:
EOF
chmod +x "$S/debian/rules"
(cd "$W" && dpkg-source -b "$S")
cp "$W/${PACKAGE}_${VERSION}.dsc" "$W/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
