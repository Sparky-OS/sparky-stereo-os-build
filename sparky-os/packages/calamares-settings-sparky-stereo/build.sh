#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Builds calamares-settings-sparky-stereo: the edition's Calamares settings in /etc/calamares, which
# Calamares reads before SparkyLinux's in /usr/share/calamares (the way Debian ships
# calamares-settings-debian). Needs only dpkg-deb.
# Last update 2026/10/15
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
PKG=calamares-settings-sparky-stereo
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
W=$(mktemp -d "${TMPDIR:-/tmp}/cal-settings.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/etc/calamares/modules" "$D/usr/lib/$PKG" "$D/usr/share/doc/$PKG"
install -m 644 "$HERE/etc/settings.conf" "$D/etc/calamares/settings.conf"
install -m 644 "$HERE"/etc/modules/*.conf "$D/etc/calamares/modules/"
install -m 755 "$HERE/lib/dual-boot" "$D/usr/lib/$PKG/dual-boot"
(cd "$D" && find etc -type f | sed 's|^|/|' | sort) >"$D/DEBIAN/conffiles"
cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s):
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: etc/calamares/settings.conf
    Calamares' settings as SparkyLinux ships them (SPDX-License-Identifier: CC0-1.0),
    with the dual-boot step

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
EOS
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: calamares, os-prober, util-linux
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo installer settings
  SparkyLinux's Calamares settings with one step added: installed beside
  Windows, the hardware clock is kept in local time so both systems show the
  right time, and Windows is listed in the boot menu.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PKG}_${VERSION}_all.deb"
