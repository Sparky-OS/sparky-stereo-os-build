#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-service-defaults: systemd drop-ins that give services of other packages a
# working default where they failed at every boot (queue item 140). Needs only dpkg-deb.
# Last update 2026/10/16
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparky-stereo-service-defaults
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
VERSION=${VERSION}+lc1
W=$(mktemp -d "${TMPDIR:-/tmp}/service-defaults.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/lib/systemd" "$D/usr/share/doc/$PKG"
cp -r "$HERE/system" "$HERE/user" "$D/usr/lib/systemd/"
find "$D/usr/lib/systemd" -type d -exec chmod 755 {} + && find "$D/usr/lib/systemd" -type f -exec chmod 644 {} +
install -D -m 755 "$HERE/NetworkManager/dispatcher.d/90-sparky-stereo-ipwatchd" \
	"$D/usr/lib/NetworkManager/dispatcher.d/90-sparky-stereo-ipwatchd"
cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
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
EOS
chmod 644 "$D/usr/share/doc/$PKG/copyright"
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ] && [ -d /run/systemd/system ]; then
	systemctl daemon-reload || true
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: systemd
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo working defaults for services
  systemd drop-ins that give services of other packages a working default
  where they failed at every boot on a fresh system: configured so they work,
  or skipped until what they need is installed. No service is removed or
  masked; each cause is reported to the package that owns it.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
