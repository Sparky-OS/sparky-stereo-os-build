#!/bin/bash
#
# Created by Daniel Ramos (Capitain Jack) and Claude Sonnet 5.5 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-firewall-apps (hand-assembled .deb, Paweł's formula): KDE Connect, and any other listed ufw
# application profile, allowed once from the local network when ufw and the profile are both on the system (ORDER 252c,
# study item J19). A dpkg trigger on /etc/ufw/applications.d runs it; a failure is kept by the edition's one engine,
# sparky-stereo-problems. Needs dpkg-deb and sparky-stereo-problems; run it in a throwaway container or on any Debian.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
VERSION=0.1.0+lc1
PKG=sparky-stereo-firewall-apps
W=$(mktemp -d "${TMPDIR:-/tmp}/firewall-apps-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/usr/share/$PKG" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" "$D/usr/lib/systemd/catalog"
install -m 755 "$HERE/bin/$PKG" "$D/usr/bin/"
install -m 644 "$HERE/data/local-network-apps" "$D/usr/share/$PKG/"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE/README.md" "$HERE/CHANGELOG" "$D/usr/share/doc/$PKG/"
# the package's own message, word for word, as journal catalogs the engine reads in the person's language
sparky-stereo-problems catalog $PKG "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1
printf 'interest-noawait /etc/ufw/applications.d\n' >"$D/DEBIAN/triggers"
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
# A rule that cannot be added is said and kept by the engine, and the package configures as debhelper's own service
# starts do: /usr/bin/sparky-stereo-firewall-apps (as root) tries again, and so does the repair the notice offers.
if [ "$1" = "configure" ] || [ "$1" = "triggered" ]; then
	/usr/bin/sparky-stereo-firewall-apps || :
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
# a problem of a package that is gone cannot be repaired by it (ORDER 350): the engine lets go of them. The rules stay: they
# are the person's firewall settings now.
if [ "$1" = "remove" ] && command -v sparky-stereo-problems >/dev/null; then
	sparky-stereo-problems clear --all sparky-stereo-firewall-apps || :
fi
if [ "$1" = "purge" ]; then
	rm -rf /var/lib/sparky-stereo-firewall-apps
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s):
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

Files: usr/share/sparky/sparky-stereo-firewall-apps/*
    Translated by Claude for Daniel Ramos (Capitain Jack), 2026
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
Depends: sparky-stereo-problems (>= 0.1.2)
Enhances: ufw, kdeconnect
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: KDE Connect through the firewall, from the local network
  The firewall is off by default. When the person turns ufw on, KDE Connect (whose package ships a ufw
  application profile) would stop answering their phone. This allows the profile once, from the private and
  link-local network ranges only, as ordinary ufw rules the person sees and can delete in System Settings, Firewall;
  a rule they removed stays removed. A rule that cannot be added is said and kept by sparky-stereo-problems.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
