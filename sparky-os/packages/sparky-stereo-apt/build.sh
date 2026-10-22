#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-apt: the apt source and the pin of the Sparky Stereo OS repository,
# the way SparkyLinux's sparky-apt ships its own. It installs
#   /etc/apt/sources.list.d/sparky-stereo.sources   (deb822, Signed-By the key of sparky-stereo-keyring)
#   /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources   (deb-multimedia, forky: the edition's FFmpeg, mpv, x264 and
#                                                     x265 are built on its packages; Signed-By the keyring of its own
#                                                     package, deb-multimedia-keyring, which the Sparky Stereo OS
#                                                     repository carries unmodified in carried/)
#   /etc/apt/preferences.d/sparky-stereo-only-ours   (Debian's and deb-multimedia's builds of our
#                                                     packages and Debian's tasks at -1; apt/make-only-ours.py)
#   /etc/apt/preferences.d/sparky-stereo             (o=Sparky Stereo OS at 1001; the file is
#                                                     ../../apt/sparky-stereo, its one source)
# It depends on sparky-stereo-keyring and on sparky-apt: the edition is built on SparkyLinux
# testing and uses its repository and key too (sparky-apt brings sparky-keyring); we never copy
# their key or files. Likewise deb-multimedia: the package deb-multimedia-keyring brings its key
# (Daniel, 2026-10-08: "we are not debian purists"). Only one package ships the pin for our origin.
# DEB_SRC=1 makes the source "Types: deb deb-src" (only once the repository publishes a
# source index for everything it carries; apt must not be sent to files that do not exist).
# Needs only dpkg-deb.
# Usage: build.sh   (output goes to $OUT, default the current folder)
# Last update 2026/10/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$PWD}
VERSION=${VERSION:-20261008.1~sparky9~0+lc1}
PKG=sparky-stereo-apt
TYPES=deb
[ "${DEB_SRC:-0}" = 1 ] && TYPES="deb deb-src"
W=$(mktemp -d "${TMPDIR:-/K3D/temp}/apt-build.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/etc/apt/sources.list.d" "$D/etc/apt/preferences.d" "$D/usr/share/doc/$PKG"

cat >"$D/etc/apt/sources.list.d/sparky-stereo.sources" <<EOS
Types: $TYPES
URIs: https://repo.sparkyos.org/
Suites: mashtabba
Components: main
Signed-By: /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
EOS
cat >"$D/etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources" <<'EOS'
# deb-multimedia (https://www.deb-multimedia.org/): the multimedia libraries and players the edition builds on. Our FFmpeg
# and mpv are built on its source packages (ffmpeg-dmo, mpv-dmo) and its x264 and x265 are the ones they use. Its builds of
# the packages we ship are blocked by sparky-stereo-only-ours; the rest of it is there for the edition's other programs.
Types: deb
URIs: https://www.deb-multimedia.org
Suites: forky
Components: main non-free
Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp
EOS
cp "$HERE/../../apt/sparky-stereo" "$D/etc/apt/preferences.d/sparky-stereo"
# Debian's and deb-multimedia's builds of our packages, and Debian's tasks, are blocked (generated from the repository index)
python3 "$HERE/../../apt/make-only-ours.py" "${REPO:-/K3D/temp/sparky-os/repo}" >/dev/null
cp "$HERE/../../apt/sparky-stereo-only-ours" "$D/etc/apt/preferences.d/sparky-stereo-only-ours"
chmod 644 "$D/etc/apt/sources.list.d/sparky-stereo.sources" "$D/etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources" \
	"$D/etc/apt/preferences.d/sparky-stereo" "$D/etc/apt/preferences.d/sparky-stereo-only-ours"

cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s): 
    Paweł "pavroo" Pijanowski
    Daniel Ramos (Capitain Jack)

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

On Debian systems, the complete text of the GNU General Public License
version 3 can be found in "/usr/share/common-licenses/GPL-3".
EOS
chmod 644 "$D/usr/share/doc/$PKG/copyright"
find "$D" -type d -exec chmod 755 {} +

SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: apt (>= 2.9.26), sparky-apt, sparky-stereo-keyring (>= $VERSION), deb-multimedia-keyring
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo OS apt source
  The apt source and pin of the Sparky Stereo OS package repository
  (https://repo.sparkyos.org/, codename mashtabba). The edition is built on
  SparkyLinux testing, so SparkyLinux's own repository comes with it, and on
  deb-multimedia's FFmpeg and mpv sources, so deb-multimedia's repository too.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
mkdir -p "$W/authoring"
cp -a "$HERE/." "$W/authoring/"
cp -a "$HERE/../../apt" "$W/authoring/apt-generator"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$W/authoring"
