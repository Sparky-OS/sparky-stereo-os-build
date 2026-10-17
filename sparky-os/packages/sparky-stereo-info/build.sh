#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-info: the system's own name, Sparky Stereo OS 9 (Mashtabba), based on
# Debian 14 (Forky). /usr/lib/os-release (base-files) and /etc/lsb-release (sparky-info) are
# diverted to *.sparky and regenerated from them, so Sparky's ID, VERSION_ID and codename
# stay as they are (Sparky's tools and repository read them) and only the names change:
# PRETTY_NAME, NAME, VERSION, VARIANT, VARIANT_ID, DEBIAN_VERSION_ID, DISTRIB_DESCRIPTION.
# A dpkg trigger regenerates them whenever Sparky updates its originals.
# Sparky Welcome's page (/usr/lib/sparky-welcome/index.html, sparky-welcome) is diverted the same way
# and regenerated with the edition's heading and credit line (welcome-header.html) in place of
# SparkyLinux's release name; the rest of the page is Sparky's own.
# Sparky Welcome is the welcome at the first login: KDE's Welcome Center (plasma-welcome) stays installed
# and in the menu, and its first-run window waits. /etc/xdg/plasma-welcomerc gives new accounts the
# installed Welcome Center's version as LastSeenVersion (kded_plasma_welcome opens the first-run window
# only when it is empty, and writes the person's own value at their first login); a trigger follows
# plasma-welcome's upgrades, so a new account never sees the update page either, while an existing account
# still gets it after an upgrade of Plasma, as KDE does.
# KInfoCenter's About page reads /etc/xdg/kcm-about-distrorc, which Debian's desktop-base sets to Debian's
# emblem and "forky/sid": it is diverted the same way and replaced by the edition's logo, name and website,
# with the version taken from os-release (kcm-about-distrorc).
# It also installs stereo-display-info, the command that prints what each display can do in
# stereo 3D and deep colour (read from its EDID) and what it is doing now.
# Last update 2026/10/17
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
VERSION=20261017~sparky9~0
PKG=sparky-stereo-info
W=$(mktemp -d /K3D/temp/sparky-os/info-build.XXXXXX)
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/usr/share/$PKG" "$D/usr/share/doc/$PKG"
cp "$HERE/edition" "$D/usr/share/$PKG/edition"
cp "$HERE/welcome-header.html" "$D/usr/share/$PKG/welcome-header.html"
install -m 644 "$HERE/kcm-about-distrorc" "$D/usr/share/$PKG/kcm-about-distrorc"
install -m 755 "$HERE/stereo-display-info" "$D/usr/bin/stereo-display-info"

cat >"$D/DEBIAN/preinst" <<'EOF'
#!/bin/sh
# preinst script
set -e
if [ "$1" = "install" ] || [ "$1" = "upgrade" ]; then
	for f in /usr/lib/os-release /etc/lsb-release /usr/lib/sparky-welcome/index.html /etc/xdg/kcm-about-distrorc; do
		if ! dpkg-divert --listpackage "$f" | grep -q sparky-stereo-info; then
			dpkg-divert --quiet --package sparky-stereo-info --add --rename --divert "$f.sparky" "$f"
			# keep the system named until postinst writes the edition's version
			[ -f "$f.sparky" ] && cp -p "$f.sparky" "$f"
		fi
	done
fi
exit 0
EOF
cat >"$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
# postinst script
set -e
. /usr/share/sparky-stereo-info/edition
osrelease() {
	src=/usr/lib/os-release.sparky
	[ -f "$src" ] || return 0
	{
		echo "PRETTY_NAME=\"$EDITION_PRETTY\""
		echo "NAME=\"$EDITION_NAME\""
		grep -E '^VERSION_ID=' "$src" || true
		echo "VERSION=\"$EDITION_VERSION\""
		echo "VARIANT=\"$EDITION_VARIANT\""
		echo "VARIANT_ID=$EDITION_VARIANT_ID"
		grep -v -E '^(PRETTY_NAME|NAME|VERSION_ID|VERSION|VARIANT|VARIANT_ID|DEBIAN_VERSION_ID)=' "$src" || true
		echo "DEBIAN_VERSION_ID=\"$DEBIAN_VERSION_ID\""
	} >/usr/lib/os-release.new
	chmod 644 /usr/lib/os-release.new
	mv /usr/lib/os-release.new /usr/lib/os-release
}
lsbrelease() {
	src=/etc/lsb-release.sparky
	[ -f "$src" ] || return 0
	sed "s|^DISTRIB_DESCRIPTION=.*|DISTRIB_DESCRIPTION=\"$EDITION_PRETTY\"|" "$src" >/etc/lsb-release.new
	grep -q '^DISTRIB_DESCRIPTION=' /etc/lsb-release.new || echo "DISTRIB_DESCRIPTION=\"$EDITION_PRETTY\"" >>/etc/lsb-release.new
	chmod 644 /etc/lsb-release.new
	mv /etc/lsb-release.new /etc/lsb-release
}
welcome() {
	src=/usr/lib/sparky-welcome/index.html.sparky
	[ -f "$src" ] || return 0
	sed -e '/<h1>.*<\/h1>/{r /usr/share/sparky-stereo-info/welcome-header.html' -e 'd}' \
		-e 's|<div id="header" style="text-align: center;">|<div id="header" style="text-align: center; height: auto;">|' \
		"$src" >/usr/lib/sparky-welcome/index.html.new
	chmod 644 /usr/lib/sparky-welcome/index.html.new
	mv /usr/lib/sparky-welcome/index.html.new /usr/lib/sparky-welcome/index.html
}
aboutdistro() {
	mkdir -p /etc/xdg
	cp /usr/share/sparky-stereo-info/kcm-about-distrorc /etc/xdg/kcm-about-distrorc.new
	chmod 644 /etc/xdg/kcm-about-distrorc.new
	mv /etc/xdg/kcm-about-distrorc.new /etc/xdg/kcm-about-distrorc
}
welcomecenter() {
	f=/etc/xdg/plasma-welcomerc
	# a file the administrator wrote is left alone
	[ -f "$f" ] && ! grep -q '^# sparky-stereo-info' "$f" && return 0
	v=$(dpkg-query -W -f '${Status} ${Version}' plasma-welcome 2>/dev/null | sed -n 's/^install ok installed \([0-9]*:\)\{0,1\}\([0-9][0-9.]*\).*/\2/p')
	if [ -z "$v" ]; then
		rm -f "$f"
		return 0
	fi
	mkdir -p /etc/xdg
	printf '# sparky-stereo-info: Sparky Welcome is the first-login welcome; the Welcome Center stays in the menu\n[General]\nLastSeenVersion=%s\n' "$v" >"$f.new"
	chmod 644 "$f.new"
	mv "$f.new" "$f"
}
case "$1" in
	configure|triggered)
		osrelease
		lsbrelease
		welcome
		aboutdistro
		welcomecenter
	;;
esac
exit 0
EOF
cat >"$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	if grep -q '^# sparky-stereo-info' /etc/xdg/plasma-welcomerc 2>/dev/null; then rm -f /etc/xdg/plasma-welcomerc; fi
fi
if [ "$1" = "remove" ] || [ "$1" = "purge" ] || [ "$1" = "abort-install" ]; then
	for f in /usr/lib/os-release /etc/lsb-release /usr/lib/sparky-welcome/index.html /etc/xdg/kcm-about-distrorc; do
		if dpkg-divert --listpackage "$f" | grep -q sparky-stereo-info; then
			rm -f "$f"
			dpkg-divert --quiet --package sparky-stereo-info --remove --rename --divert "$f.sparky" "$f"
		fi
	done
fi
exit 0
EOF
printf 'interest-noawait /usr/lib/os-release.sparky\ninterest-noawait /etc/lsb-release.sparky\ninterest-noawait /usr/lib/sparky-welcome/index.html.sparky\ninterest-noawait /usr/lib/x86_64-linux-gnu/qt6/plugins/kf6/kded/kded_plasma_welcome.so\n' >"$D/DEBIAN/triggers"
chmod 755 "$D/DEBIAN/preinst" "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"

cat >"$D/usr/share/doc/$PKG/copyright" <<'EOF'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s): 
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: * 
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

License:

    This package is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.
 
    This package is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
 
    You should have received a copy of the GNU General Public License
    along with this package; if not, see <http://www.gnu.org/licenses/>.

On Debian systems, the complete text of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-3'.
EOF
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: base-files, edid-decode
Recommends: hwdata, pciutils, mesa-utils, vulkan-tools
Suggests: displaycal
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo OS info
  The system's own name: Sparky Stereo OS 9 (Mashtabba), based on Debian 14
  (Forky), in os-release and lsb-release, keeping Sparky's ID and codename,
  and in Sparky Welcome's heading with the edition's credit line. Sparky
  Welcome is the welcome at the first login; KDE's Welcome Center stays in
  the menu. KInfoCenter's About page shows the edition's logo, name and
  website, with the version from os-release.
  Also the stereo-display-info command: what each display can do in stereo 3D
  and deep colour, and what it is doing now.
EOF
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PKG}_${VERSION}_all.deb"
