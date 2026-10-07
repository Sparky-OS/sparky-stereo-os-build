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
# It also installs stereo-display-info, the command that prints what each display can do in
# stereo 3D and deep colour (read from its EDID) and what it is doing now.
# Last update 2026/10/05
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
VERSION=20261005~sparky9~0
PKG=sparky-stereo-info
W=$(mktemp -d /K3D/temp/sparky-os/info-build.XXXXXX)
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/usr/share/$PKG" "$D/usr/share/doc/$PKG"
cp "$HERE/edition" "$D/usr/share/$PKG/edition"
install -m 755 "$HERE/stereo-display-info" "$D/usr/bin/stereo-display-info"

cat >"$D/DEBIAN/preinst" <<'EOF'
#!/bin/sh
# preinst script
set -e
if [ "$1" = "install" ] || [ "$1" = "upgrade" ]; then
	for f in /usr/lib/os-release /etc/lsb-release; do
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
case "$1" in
	configure|triggered)
		osrelease
		lsbrelease
	;;
esac
exit 0
EOF
cat >"$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ] || [ "$1" = "abort-install" ]; then
	for f in /usr/lib/os-release /etc/lsb-release; do
		if dpkg-divert --listpackage "$f" | grep -q sparky-stereo-info; then
			rm -f "$f"
			dpkg-divert --quiet --package sparky-stereo-info --remove --rename --divert "$f.sparky" "$f"
		fi
	done
fi
exit 0
EOF
printf 'interest-noawait /usr/lib/os-release.sparky\ninterest-noawait /etc/lsb-release.sparky\n' >"$D/DEBIAN/triggers"
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
  (Forky), in os-release and lsb-release, keeping Sparky's ID and codename.
  Also the stereo-display-info command: what each display can do in stereo 3D
  and deep colour, and what it is doing now.
EOF
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PKG}_${VERSION}_all.deb"
