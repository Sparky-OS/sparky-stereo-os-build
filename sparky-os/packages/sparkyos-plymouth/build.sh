#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Builds sparkyos-plymouth, the SparkyOS boot splash, from the artwork repository's plymouth/ folder
# (ART): the themes sparkyos-stereo (every screen: both eyes on a stereo output, which the edition's
# Plymouth gives a theme declaring Stereo=full-side-by-side, one picture elsewhere) and sparkyos (2D),
# installed where its install.sh puts them. sparkyos-stereo becomes the default theme, as sparky-plymouth
# makes sparky-blue SparkyLinux's. sparky-plymouth sets sparky-blue again at every upgrade, whatever theme
# was chosen; a trigger on its theme then sets this package's default back, when this package had set it.
# Removing this package gives sparky-blue back.
# Last update 2026/10/16
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ART=${ART:-/K3D/temp/sparky-os/artwork-repo/plymouth}
OUT=${OUT:-/K3D/temp/sparky-os/repo}
PKG=sparkyos-plymouth
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
VERSION=$VERSION+lc1
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
DEFAULT=sparkyos-stereo
current() { plymouth-set-default-theme 2>/dev/null || true; }
case "$1" in
	configure)
		# a first install makes sparkyos-stereo the default; an upgrade keeps the owner's choice, and moves
		# the default this package set before 9~20261016.1 (sparkyos) to sparkyos-stereo
		cur=$(current)
		if [ -z "$2" ] || [ "$cur" = sparky-blue ] || { dpkg --compare-versions "$2" lt 9~20261016.1 && [ "$cur" = sparkyos ] && [ "$(cat "$STATE" 2>/dev/null)" = sparkyos ]; }; then
			plymouth-set-default-theme "$DEFAULT"
			mkdir -p /var/lib/sparkyos-plymouth
			echo "$DEFAULT" >"$STATE"
		elif [ "$cur" != "$(cat "$STATE" 2>/dev/null || true)" ]; then
			# the owner chose another theme: the trigger below leaves it alone from now on
			rm -f "$STATE"
		fi
	;;
	triggered)
		# sparky-plymouth's upgrade sets sparky-blue: this package's default again, if it had set it
		s=$(cat "$STATE" 2>/dev/null || true)
		if [ "$(current)" = sparky-blue ] && [ -n "$s" ] && [ -e "/usr/share/plymouth/themes/$s/$s.plymouth" ]; then
			plymouth-set-default-theme "$s"
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
	# the configured theme, read from the file: the theme's own files are gone by now
	s=$(cat /var/lib/sparkyos-plymouth/theme 2>/dev/null || true)
	t=$(sed -n 's/^[[:space:]]*Theme[[:space:]]*=[[:space:]]*//p' /etc/plymouth/plymouthd.conf 2>/dev/null | tail -n1)
	if [ -n "$s" ] && [ "$t" = "$s" ] && [ -e /usr/share/plymouth/themes/sparky-blue/sparky-blue.plymouth ]; then
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
  EDITION wordmark. Two themes: sparkyos-stereo, the default, in stereo 3D
  on a stereo output and in 2D elsewhere, and sparkyos, in 2D.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
mkdir -p "$W/authoring"
cp -a "$HERE/." "$W/authoring/"
cp -a "$ART" "$W/authoring/artwork"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$W/authoring"
