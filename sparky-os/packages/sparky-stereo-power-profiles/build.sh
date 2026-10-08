#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=20261008.1~sparky9~0
PACKAGE=sparky-stereo-power-profiles
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.power-profiles.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
install -Dm644 "$HERE/share/powerdevilrc" "$D/etc/xdg/powerdevilrc"
install -Dm644 "$HERE/share/kscreenlockerrc" "$D/etc/xdg/kscreenlockerrc"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: power-profiles-daemon (>= 0.30), powerdevil (>= 6.7), sparky-stereo-powerdevil-policy (>= 1)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: KDE power and idle defaults for Sparky Stereo OS
  Performance on AC, balanced on battery and power saver at low battery.
  Desktop idle keeps the machine awake; plugged laptops sleep after four hours.
  The user's own Plasma settings take precedence.
EOF
printf '%s\n' /etc/xdg/kscreenlockerrc /etc/xdg/powerdevilrc >"$D/DEBIAN/conffiles"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_all.deb"

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
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
Depends: power-profiles-daemon (>= 0.30), powerdevil (>= 6.7), sparky-stereo-powerdevil-policy (>= 1)
Description: KDE power and idle defaults for Sparky Stereo OS
 Power profiles, idle, locking, buttons and lid actions through Plasma settings.
EOF
cat >"$S/debian/changelog" <<EOF
$PACKAGE ($VERSION) unstable; urgency=medium

  * Apply Daniel's idle, locking, shutdown-button and lid defaults.
  * Require the profile-aware PowerDevil policy implementation.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 08 Oct 2026 12:15:00 -0300
EOF
cp "$HERE/copyright" "$S/debian/copyright"
mkdir -p "$S/debian/source"
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
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
