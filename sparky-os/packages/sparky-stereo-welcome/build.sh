#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-welcome: the edition's pages in KDE's Welcome Center (Plasma Welcome), shown first, before
# KDE's own pages (ORDER 63 and 720). Needs python3, python3-pil, dpkg-deb, and what lean.standalone needs (node-acorn
# to check the QML).
# Last update 2026/11/25 (milestone 2: the remaining pages, the Upgrade helper, Sparky Welcome's first run skipped, the
# touch screen mark, the languages)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparky-stereo-welcome
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
[ -n "$VERSION" ] || { echo "no version on the second line of CHANGELOG" >&2; exit 1; }
VERSION=${VERSION}+lc1
W=$(mktemp -d "${TMPDIR:-/tmp}/welcome-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
DROPIN='usr/lib/systemd/user/app-sparky\x2dwelcome\x2dfirst@autostart.service.d'
mkdir -p "$D/DEBIAN" "$D/usr/share/plasma/plasma-welcome/first-pages" "$D/usr/share/plasma/plasma-welcome/extra-pages" \
	"$D/usr/share/$PKG/pictures" "$D/usr/share/$PKG/touch-screen/xdg" "$D/usr/share/doc/$PKG" "$D/usr/bin" "$D/$DROPIN" \
	"$D/etc/xdg/plasma-workspace/env"
install -m 644 "$HERE"/first-pages/*.qml "$D/usr/share/plasma/plasma-welcome/first-pages/"
install -m 644 "$HERE"/extra-pages/*.qml "$D/usr/share/plasma/plasma-welcome/extra-pages/"
install -m 755 "$HERE/bin/sparky-stereo-welcome-upgrade" "$D/usr/bin/"
install -m 644 "$HERE/share/systemd-user/sparky-stereo-welcome.conf" "$D/$DROPIN/"
install -m 644 "$HERE/share/plasma-env/sparky-stereo-welcome-touch.sh" "$D/etc/xdg/plasma-workspace/env/"
install -m 644 "$HERE/share/touch-screen/xdg/plasma-welcomerc" "$D/usr/share/$PKG/touch-screen/xdg/"
mkdir -p "$D/usr/lib/live/config"
install -m 755 "$HERE/share/live/1187-sparky-stereo-welcome" "$D/usr/lib/live/config/"
# the pages' words in the edition's languages: po/LANG.po, made from po/sparky-stereo-welcome.pot (tools/extract-messages.sh)
for po in "$HERE"/po/*.po; do
	[ -e "$po" ] || continue
	lang=$(basename "$po" .po)
	mkdir -p "$D/usr/share/locale/$lang/LC_MESSAGES"
	msgfmt --check -o "$D/usr/share/locale/$lang/LC_MESSAGES/$PKG.mo" "$po"
	chmod 644 "$D/usr/share/locale/$lang/LC_MESSAGES/$PKG.mo"
done
python3 "$HERE/tools/make-pictures.py" "$HERE/../sparky-stereo-calamares-branding/usr/share/calamares/branding/sparky-stereo" \
	"$D/usr/share/$PKG/pictures"
chmod 644 "$D/usr/share/$PKG/pictures"/*
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"

cat >"$D/usr/share/doc/$PKG/copyright" <<'EOF'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s):
    Paweł "pavroo" Pijanowski
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3+

Files: usr/share/sparky-stereo-welcome/pictures/*
    Cut from the installer slides of the SparkyOS artwork (sparky-stereo-calamares-branding's slide11-any-screen.pns,
    the same rectangle of each eye): the Sparky Black background with pictures drawn for the set.
    Copyright (C) 2018-2026 Daniel Ramos (Capitain Jack)
    License: GPL-2+

The pages are shown by KDE's Welcome Center (plasma-welcome, by Felipe Kinoshita, Nate Graham, Oliver Beard and the
KDE community, GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL), which is not part of this package.
SparkyLinux's own first-run window, Sparky Welcome, is Paweł "pavroo" Pijanowski's work.

Files: usr/share/locale/de/* usr/share/locale/es/* usr/share/locale/pl/*
    Sparky Welcome's own words for its buttons and headings in these languages are kept as its translators made them
    (sparky-welcome's lang files, first made by Piotr "MoroS" Mrożek; translators as sparky-welcome's copyright file
    names them: Roy, jidan, Goro86, depaz, Jouko Tiilikainen, nemomen, Yodel Sinatra, ChourS, XalisRatt).
    License: GPL-3+

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
Public License can be found in `/usr/share/common-licenses/GPL-3', version 2 in
`/usr/share/common-licenses/GPL-2'.
EOF
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: kscreen, kwin-common, libstereo-layer1 (>= 1.23.4), plasma-welcome (>= 6.7.4-1+stereo3d2~), qml6-module-qtquick-shapes, systemsettings, sparky-about, sparky-aptus-appcenter, sparky-aptus-upgrade, sparky-remsu, sparky-stereo-info, sparky-su, sparky-system
Breaks: sparky-stereo-info (<< 20261125~sparky9~0)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: Sparky Stereo OS pages in KDE's Welcome Center
  The window a new account sees at its first login is KDE's Welcome Center,
  with the edition's pages first: Sparky Stereo OS in one screen, the 3D
  screens it shows the desktop on and where Display Configuration is; and Point,
  Then Type, on the window under the pointer getting the keys, why, and where
  to change it. After KDE's own pages: touch and tablet mode; every element of
  SparkyLinux's own welcome window (Sparky Welcome, which stays in the menu and
  no longer opens by itself at a first login); and what a tester can send. On
  a 3D screen the picture and the drawing have depth; on a 2D screen the pages
  are flat.
EOF
printf '%s\n' /etc/xdg/plasma-workspace/env/sparky-stereo-welcome-touch.sh >"$D/DEBIAN/conffiles"
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
