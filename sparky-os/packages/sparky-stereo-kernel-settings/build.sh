#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/09
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/09
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=20261009~sparky9~0
PACKAGE=sparky-stereo-kernel-settings
DEPENDS='libpam-modules, systemd, systemd-zram-generator, udev'
FILES='etc/security/limits.d/20-sparky-audio.conf usr/lib/modules-load.d/sparky-stereo.conf usr/lib/sysctl.d/70-sparky-stereo.conf usr/lib/systemd/zram-generator.conf.d/sparky-stereo.conf usr/lib/tmpfiles.d/sparky-thp.conf usr/lib/udev/rules.d/30-sparky-zram.rules usr/lib/udev/rules.d/60-sparky-block.rules usr/lib/udev/rules.d/70-sparky-ntsync.rules usr/lib/udev/rules.d/99-sparky-audio.rules'
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.kernel-settings.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
for f in $FILES; do install -Dm644 "$HERE/$f" "$D/$f"; done
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOT
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Kernel tunables for Sparky Stereo OS
  Sysctl, udev, tmpfiles, modules-load, zram and audio-limit settings that replace
  kernel patches of performance kernels. Closes kexec after boot.
EOT
printf '%s\n' /etc/security/limits.d/20-sparky-audio.conf >"$D/DEBIAN/conffiles"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_all.deb"

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<EOT
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
Depends: $DEPENDS
Description: Kernel tunables for Sparky Stereo OS
 Sysctl, udev, tmpfiles, modules-load, zram and audio-limit settings.
EOT
cat >"$S/debian/changelog" <<EOT
$PACKAGE ($VERSION) unstable; urgency=medium

  * First release: kernel tunables as user-space files.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Fri, 09 Oct 2026 12:00:00 -0300
EOT
cp "$HERE/copyright" "$S/debian/copyright"
mkdir -p "$S/debian/source"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOT'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_all.deb System optional
clean:
build:
EOT
chmod +x "$S/debian/rules"
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
