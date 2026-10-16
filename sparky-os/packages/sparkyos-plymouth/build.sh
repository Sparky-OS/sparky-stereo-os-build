#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Builds sparkyos-plymouth, the SparkyOS boot splash, from the artwork repository's plymouth/ folder
# (ART): the themes sparkyos (every screen) and sparkyos-stereo (a 3D display in side-by-side mode),
# installed where its install.sh puts them. sparkyos becomes the default theme, as sparky-plymouth makes
# sparky-blue SparkyLinux's. sparky-plymouth sets sparky-blue again at every upgrade, whatever theme
# was chosen; a trigger on its theme then sets sparkyos back, when this package had made it the default.
# Removing this package gives sparky-blue back.
# Last update 2026/10/16
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ART=${ART:-/K3D/temp/sparky-os/artwork-repo/plymouth}
OUT=${OUT:-/K3D/temp/sparky-os/repo}
PKG=sparkyos-plymouth
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
W=$(mktemp -d "${TMPDIR:-/tmp}/sparkyos-plymouth.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/share/plymouth/themes" "$D/usr/share/doc/$PKG"
for t in sparkyos sparkyos-stereo; do
	cp -r "$ART/$t" "$D/usr/share/plymouth/themes/"
done
cp "$ART/copyright" "$D/usr/share/doc/$PKG/copyright"
cp "$ART/README.md" "$D/usr/share/doc/$PKG/README.md"
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
STATE=/var/lib/sparkyos-plymouth/theme
current() { plymouth-set-default-theme 2>/dev/null || true; }
case "$1" in
	configure)
		# a first install makes sparkyos the default; an upgrade keeps the owner's choice
		if [ -z "$2" ] || [ "$(current)" = sparky-blue ]; then
			plymouth-set-default-theme sparkyos
			mkdir -p /var/lib/sparkyos-plymouth
			echo sparkyos >"$STATE"
		fi
	;;
	triggered)
		# sparky-plymouth's upgrade sets sparky-blue: sparkyos again, if it was ours before
		if [ "$(current)" = sparky-blue ] && [ "$(cat "$STATE" 2>/dev/null)" = sparkyos ]; then
			plymouth-set-default-theme sparkyos
		fi
	;;
esac
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	if [ "$(cat /var/lib/sparkyos-plymouth/theme 2>/dev/null)" = sparkyos ] && [ -e /usr/share/plymouth/themes/sparky-blue/sparky-blue.plymouth ]; then
		plymouth-set-default-theme sparky-blue || true
	fi
	rm -rf /var/lib/sparkyos-plymouth
fi
exit 0
EOS
printf 'interest-noawait /usr/share/plymouth/themes/sparky-blue\nactivate-noawait update-initramfs\n' >"$D/DEBIAN/triggers"
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
find "$D" -path "$D/DEBIAN" -prune -o -type d -exec chmod 755 {} + ; find "$D" -path "$D/DEBIAN" -prune -o -type f -exec chmod 644 {} +
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: plymouth, plymouth-themes
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: SparkyOS Plymouth Themes
  The SparkyOS boot splash: the Debian swirl with its orbits and electrons
  on the Sparky background, and the SPARKYOS / POWERED BY DEBIAN / STEREO 3D
  EDITION wordmark. Two themes: sparkyos for every screen, the default, and
  sparkyos-stereo for a 3D display in side-by-side mode.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PKG}_${VERSION}_all.deb"
