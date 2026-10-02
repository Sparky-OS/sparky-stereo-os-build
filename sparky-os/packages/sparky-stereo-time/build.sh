#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-time: chrony's time sources from the timezone. The country's official
# service (NTS where it offers it) from a TSV of verified rows, else Debian's pool. A oneshot
# service runs at boot before chrony; a watcher runs it again when timedated reports a new timezone.
# Needs only dpkg-deb; run it in a throwaway container or on any Debian.
# Last update 2026/10/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
VERSION=20261002.3~sparky9~0
PKG=sparky-stereo-time
W=$(mktemp -d "${TMPDIR:-/K3D/temp}/time-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
S=$D/usr/share/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$S" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" \
	"$D/etc/chrony/conf.d" "$D/usr/lib/systemd/system/multi-user.target.wants"

install -m 755 "$HERE/bin/sparky-stereo-time" "$HERE/bin/sparky-stereo-time-watch" "$D/usr/bin/"
install -m 644 "$HERE/data/ntp-countries.tsv" "$S/ntp-countries.tsv"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE"/systemd/sparky-stereo-time.service "$HERE"/systemd/sparky-stereo-time-watch.service \
	"$D/usr/lib/systemd/system/"
cat >"$D/etc/chrony/conf.d/sparky-stereo.conf" <<'EOS'
# Sparky Stereo OS: sparky-stereo-time. A machine with a wrong clock (no RTC) cannot check the
# NTS-KE certificate dates, and with authselectmode prefer no plain source corrects it first.
nocerttimecheck 1
EOS
chmod 644 "$D/etc/chrony/conf.d/sparky-stereo.conf"
printf '/etc/chrony/conf.d/sparky-stereo.conf\n' >"$D/DEBIAN/conffiles"
ln -s ../sparky-stereo-time.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-time.service"
ln -s ../sparky-stereo-time-watch.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-time-watch.service"

cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ]; then
	/usr/bin/sparky-stereo-time || true
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
		systemctl restart sparky-stereo-time-watch.service || true
	fi
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	rm -f /etc/chrony/sources.d/sparky-stereo.sources
	# chrony.conf itself is never touched; our generated conf.d snippet goes, chrony restarts once
	changed=0
	[ -f /etc/chrony/conf.d/sparky-stereo-auth.conf ] && { rm -f /etc/chrony/conf.d/sparky-stereo-auth.conf; changed=1; }
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
		[ "$changed" = 1 ] && { systemctl try-restart chrony.service 2>/dev/null || true; }
	fi
	[ "$changed" = 1 ] || { chronyc reload sources >/dev/null 2>&1 || true; }
fi
exit 0
EOS
cat >"$D/DEBIAN/prerm" <<'EOS'
#!/bin/sh
# prerm script
set -e
if { [ "$1" = "remove" ] || [ "$1" = "upgrade" ]; } && [ -d /run/systemd/system ]; then
	systemctl stop sparky-stereo-time-watch.service 2>/dev/null || true
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm" "$D/DEBIAN/prerm"

cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, an edition of SparkyLinux (https://sparkylinux.org), created by Paweł "pavroo" Pijanowski <pavroo@onet.eu> and Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>.

Upstream Author(s):
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

Files: usr/bin/sparky-stereo-time
    The timezone-to-country lookup follows sparky-ntp-server (2025)
    Copyright (C) 2025 Daniel Ramos (Capitain Jack)
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
Depends: ca-certificates, chrony
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo time servers
  Sets chrony's time sources from the timezone: the country's official
  service, with NTS where it offers it, or Debian's pool where it has none.
  Countries with two or more NTS servers use authselectmode prefer, so Debian's
  pool is never selected next to them. chrony.conf is not modified.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PKG}_${VERSION}_all.deb"
