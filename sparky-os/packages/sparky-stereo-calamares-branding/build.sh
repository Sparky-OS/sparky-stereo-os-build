#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/14
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION='20261014~sparky9~0'
PACKAGE=sparky-stereo-calamares-branding
DEPENDS='calamares, libstereo-layer1 (>= 1.4.1), qml6-module-qtquick-window'
RECOMMENDS='calamares (>= 3.4.3~sparky9~4-1+stereo3d1)'
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.calamares-branding.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
cp -a "$HERE/usr" "$HERE/etc" "$D/"
find "$D" -type d -exec chmod 755 {} +
find "$D" -type f -exec chmod 644 {} +
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOT
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Recommends: $RECOMMENDS
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Stereo 3D slideshow for the installer
  Six slides of Sparky Stereo OS in stereo 3D for Calamares' install
  progress page, shown through the shared stereo picture item: each slide is
  its own surface for the compositor, the rest of the installer stays 2D, and
  a screen with one eye shows the slide's left view.
EOT
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
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
Recommends: $RECOMMENDS
Description: Stereo 3D slideshow for the installer
 Six slides of Sparky Stereo OS in stereo 3D for Calamares' install progress page.
EOT
cat >"$S/debian/changelog" <<EOT
$PACKAGE ($VERSION) unstable; urgency=medium

  * First version: the installer's slideshow as six stereo slides through
    stereo-layer's QML item, run in a window of its own (slideshowWindow, in
    the patched calamares package); the branding is found first in
    /etc/calamares/branding, so SparkyLinux's own files stay as they are.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Wed, 14 Oct 2026 22:40:00 -0300
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
