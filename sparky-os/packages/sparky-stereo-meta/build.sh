#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Builds the edition's meta-packages from sparky-os/lists/*.list and lists/roles.tsv (lists/make-meta.py
# writes the control files and names the packages): sparky-stereo, sparky-stereo-desktop,
# sparky-stereo-hardware-support, sparky-stereo-languages, sparky-stereo-system, the role tasks
# task-sparky-stereo-<role> and task-sparky-<role>, sparky-stereo-tasks (tasksel) and the
# transitional sparky-stereo-gaming.
# The kernel pair linux-image-sparky-stereo and linux-headers-sparky-stereo is versioned after
# the kernel in the repository (rebuild after a kernel bump). Each is a control file and a copyright file. Version: the build date.
# Last update 2026/10/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
VERSION=${VERSION:-$(date +%Y%m%d)}   # second build of a day: VERSION=YYYYMMDD.1
W=$(mktemp -d /K3D/temp/sparky-os/meta-build.XXXXXX)
trap 'rm -rf "$W"' EXIT

PKGS=$(python3 "$HERE/../../lists/make-meta.py" --list)
for PKG in $PKGS; do
	mkdir -p "$W/$PKG/DEBIAN" "$W/$PKG/usr/share/doc/$PKG"
	cat >"$W/$PKG/usr/share/doc/$PKG/copyright" <<'EOT'
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
EOT
done
python3 "$HERE/../../lists/make-meta.py" "$VERSION" "$W"
mkdir -p "$OUT"
for PKG in $PKGS; do
	(cd "$W/$PKG" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
	V=$(sed -n 's/^Version: //p' "$W/$PKG/DEBIAN/control")
	dpkg-deb --root-owner-group -Zxz -b "$W/$PKG" "$OUT/${PKG}_${V}_all.deb" >/dev/null
	echo "built $OUT/${PKG}_${V}_all.deb"
done
