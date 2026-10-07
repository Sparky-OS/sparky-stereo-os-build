#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-keyring: the public key of the Sparky Stereo OS repository, nothing
# else, the way SparkyLinux's sparky-keyring ships only its key. It installs
#   /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc   (ASCII armoured)
# The repository's sources file and pin come in the sparky-stereo-apt package.
# Needs only dpkg-deb and gpg.
# Usage: build.sh [PUBLIC-KEY-FILE]   (default: sparky-stereo-repo.asc beside this script, the
#   repository's public key, fingerprint 10DF D38D AD1E 4808 BC68 8E5A 945E 5D07 9A2A 0B9C;
#   tests pass their own throwaway key)
# Output goes to $OUT (default: the current folder; point it at the repository folder yourself).
# Last update 2026/10/05
set -euo pipefail
KEY=${1:-$(cd "$(dirname "$0")" && pwd)/sparky-stereo-repo.asc}
[ -s "$KEY" ] || { echo "$KEY is empty or missing" >&2; exit 1; }
OUT=${OUT:-$PWD}
VERSION=${VERSION:-20261005.1~sparky9~0}
PKG=sparky-stereo-keyring
W=$(mktemp -d "${TMPDIR:-/K3D/temp}/keyring-build.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/etc/apt/trusted.gpg.d" "$D/usr/share/doc/$PKG"

head -c 40 "$KEY" | grep -q -- '-----BEGIN PGP PUBLIC KEY BLOCK-----' ||
	{ echo "$KEY is not an ASCII armoured public key" >&2; exit 1; }
cp "$KEY" "$D/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc"
chmod 644 "$D/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc"
# it must be a public key, with no secret part
info=$(gpg --show-keys --with-colons "$D/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc")
echo "$info" | grep -q '^pub:' || { echo "$KEY holds no public key" >&2; exit 1; }
if echo "$info" | grep -q '^sec:'; then echo "$KEY holds a secret key, refusing" >&2; exit 1; fi

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
Depends: gnupg | gnupg2
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo OS repository key
  The signing key of the Sparky Stereo OS package repository
  (https://repo.sparkyos.org/), for apt.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PKG}_${VERSION}_all.deb" >/dev/null
echo "built $OUT/${PKG}_${VERSION}_all.deb"
