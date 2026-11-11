#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-service-defaults: systemd drop-ins that give services of other packages a
# working default where they failed at every boot (queue item 140), and, since 0.1.3 (ORDER 346c),
# say and keep each one's failure instead of skipping it (sparky-stereo-service-problem@, problems.py), kept since
# ORDER 350 by the edition's one engine, sparky-stereo-problems.
# Needs dpkg-deb and sparky-stereo-problems (its catalog command).
# Last update 2026/11/02
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
mkdir -p "$D/DEBIAN" "$D/usr/lib/systemd" "$D/usr/share/doc/$PKG" "$D/usr/bin" "$D/usr/lib/$PKG" \
	"$D/usr/share/sparky/$PKG" "$D/usr/lib/systemd/catalog"
cp -r "$HERE/system" "$HERE/user" "$D/usr/lib/systemd/"
# the package's own messages, word for word, as journal catalogs the engine reads in the person's language (ORDER 350)
sparky-stereo-problems catalog $PKG "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL13
find "$D/usr/lib/systemd" -type d -exec chmod 755 {} + && find "$D/usr/lib/systemd" -type f -exec chmod 644 {} +
install -D -m 755 "$HERE/NetworkManager/dispatcher.d/90-sparky-stereo-ipwatchd" \
	"$D/usr/lib/NetworkManager/dispatcher.d/90-sparky-stereo-ipwatchd"
install -m 755 "$HERE/bin/sparky-stereo-service-defaults" "$D/usr/bin/"
install -m 644 "$HERE/lib/problems.py" "$D/usr/lib/$PKG/problems.py"
install -m 755 "$HERE/lib/clamav-updaters" "$D/usr/lib/$PKG/clamav-updaters"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
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
# A failed daemon-reload is said and kept (problems.py), and the package configures, as debhelper's own unit
# handling does; sparky-stereo-service-defaults repair runs it again.
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ] && [ -d /run/systemd/system ]; then
	python3 /usr/lib/sparky-stereo-service-defaults/problems.py run systemd-reload LOCAL21 -- systemctl daemon-reload || :
fi
# ORDER 460: ClamAV's two updaters (see the helper): once, when this version first arrives, and as the engine's Repair
if [ "$1" = "configure" ] && { [ -z "${2:-}" ] || dpkg --compare-versions "$2" lt 0.1.5~; }; then
	sparky-stereo-problems run --machine --repair '["/usr/lib/sparky-stereo-service-defaults/clamav-updaters"]' \
		sparky-stereo-service-defaults clamav-updaters LOCAL23 -- /usr/lib/sparky-stereo-service-defaults/clamav-updaters || :
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
# a problem of a package that is gone cannot be repaired by it (ORDER 350): the engine lets go of them, and says
# what it could not
if [ "$1" = "remove" ] && command -v sparky-stereo-problems >/dev/null; then
	sparky-stereo-problems clear --all sparky-stereo-service-defaults || :
fi
if [ "$1" = "purge" ]; then
	rm -rf /var/lib/sparky-stereo-service-defaults
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: systemd, python3, iproute2, sparky-stereo-problems (>= 0.1.0)
Breaks: snmptt (<< 1.5-3+sparky1~), pkcs11-daemon (<< 0.4.1-5+sparky1~), xfsprogs (<< 7.2.0-1+sparky1~), urfkill (<< 0.5.0-8+sparky1~)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo working defaults for services
  systemd drop-ins that give services of other packages a working default
  where they failed at every boot on a fresh system. What a service needs is
  supplied (the edition's builds of snmptt, pkcs11-daemon, xfsprogs and urfkill); a
  service that still cannot start is said and kept, with the reason and what
  to do, and shown in the session, never skipped behind the person's back.
  No service is removed or masked; each cause is reported to the package that
  owns it.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
