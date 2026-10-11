#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
# Builds sparky-stereo-marble-planets: the map themes of the Moon and the planets that Marble offers in its
# "Download Maps" dialog, from KDE's own map sources (maps.list), checked against their SHA-256 before use.
# OUT: the output directory; CACHE (optional): a directory that already holds the downloaded zip files
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
PKG=sparky-stereo-marble-planets
VERSION=20261010~sparky9~0
mkdir -p "$OUT"
CACHE=${CACHE:-$OUT/.cache-$PKG}
mkdir -p "$CACHE"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PKG" "$D/usr/share/marble/data/maps"
grep -v '^#' "$HERE/maps.list" | while IFS='|' read -r id url sha name version licence credit; do
	zip=$CACHE/$id-marblemap.zip
	if [ ! -f "$zip" ] || ! echo "$sha  $zip" | sha256sum -c --quiet - 2>/dev/null; then
		curl -fsSL -o "$zip" "$url"
	fi
	echo "$sha  $zip" | sha256sum -c --quiet -
	# Each zip holds <body>/<theme>/, as Marble's own download puts it in the user's map folder
	unzip -q -o "$zip" -d "$D/usr/share/marble/data/maps"
done
# One theme carries a Windows thumbnail cache, which is not part of the map
find "$D/usr/share/marble/data/maps" -name Thumbs.db -delete
find "$D/usr/share/marble/data/maps" -type d -exec chmod 755 {} +
find "$D/usr/share/marble/data/maps" -type f -exec chmod 644 {} +
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
install -m644 "$HERE/maps.list" "$D/usr/share/doc/$PKG/maps.list"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOC
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: marble-data
Section: Science
Priority: optional
Homepage: https://sparkylinux.org
Description: Marble maps of the Moon and the planets for Sparky Stereo OS
  The map themes of Mercury, Venus, Mars, the Moon and moons of Jupiter and
  Saturn that Marble offers in its Download Maps dialog, from KDE's own map
  sources, installed for every user: historical and NASA/USGS maps, all in
  the public domain. Marble shows them in the Map View under each body.
EOC
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb"
sync
