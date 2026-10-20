#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION='20261016.1~sparky9~0+lc1'
PACKAGE=sparky-stereo-calamares-branding
DEPENDS='calamares, libstereo-layer1 (>= 1.4.1), qml6-module-qtquick-window'
RECOMMENDS='calamares (>= 3.4.3~sparky9~4-1+stereo3d1)'
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.calamares-branding.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
cp -a "$HERE/usr" "$HERE/etc" "$D/"
# the translations: a .qm only from a .ts with finished translations (an unfinished string falls back to its English source)
LANGDIR=$D/usr/share/calamares/branding/sparky-stereo/lang
mkdir -p "$LANGDIR"
LRELEASE=$(command -v lrelease6 || command -v lrelease || ls /usr/lib/qt6/bin/lrelease)
for ts in "$HERE"/translations/calamares-sparky_*.ts; do
	qm=$LANGDIR/$(basename "${ts%.ts}").qm
	"$LRELEASE" -silent "$ts" -qm "$qm" || true
	if ! grep -q '<translation>' "$ts"; then rm -f "$qm"; fi
done
rmdir --ignore-fail-on-non-empty "$LANGDIR"
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
  Twenty-three slides of Sparky Stereo OS in stereo 3D for Calamares' install
  progress page, shown through the shared stereo picture item: each slide is
  its own surface for the compositor, the rest of the installer stays 2D, and
  a screen with one eye shows the slide's left view. The words are text in
  the reader's language, set at the screen plane.
EOT
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
sync
