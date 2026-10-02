#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/02

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-"$HERE/../../../../out"}
VERSION=0.1.0
PKG=sparky-stereo-locales
SHARE=/usr/share/$PKG
WORK=$(mktemp -d "$HERE/../../../../out/build.XXXXXX")

D=$WORK/$PKG
rm -rf "$D"
mkdir -p "$D/DEBIAN" \
	"$D/usr/bin" \
	"$D$SHARE/lang" \
	"$D$SHARE/data" \
	"$D/usr/share/applications" \
	"$D/usr/share/polkit-1/actions" \
	"$D/usr/share/doc/$PKG"
install -m 0755 "$HERE/bin/$PKG" "$D/usr/bin/$PKG"
install -m 0644 "$HERE/lang/en" "$HERE/lang/pt_BR" "$D$SHARE/lang/"
install -m 0644 "$HERE/data/language" "$D$SHARE/data/language"
install -m 0644 "$HERE/../../lists/languages.list" "$D$SHARE/languages.list"
install -m 0644 "$HERE/share/$PKG.desktop" "$D/usr/share/applications/$PKG.desktop"
install -m 0644 "$HERE/share/org.$PKG.policy" "$D/usr/share/polkit-1/actions/org.$PKG.policy"
install -m 0644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
cat >"$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = purge ]; then
	rm -f /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales
fi
exit 0
EOF
chmod 0755 "$D/DEBIAN/postrm"

cat >"$D/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $(du -sk --exclude=DEBIAN "$D" | cut -f1)
Depends: apt, dpkg, yad
Recommends: sparky-remsu
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo locale tool
  Removes and restores language packages, keeping only what you use.
EOF
(
	cd "$D"
	find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort |
		tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums
)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb"
rm -rf "$WORK"
