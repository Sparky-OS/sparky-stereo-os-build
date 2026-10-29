#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-ffmpeg-fdk: the one-command helper that rebuilds the edition's FFmpeg on the user's own computer with
# Fraunhofer's AAC encoder (libfdk_aac). The edition's FFmpeg is built without it (FFmpeg's LICENSE.md calls a GPL build that
# includes it unredistributable); a build made by this helper is for that computer only. It installs
#   /usr/bin/sparky-stereo-ffmpeg-fdk                              the command
#   /usr/lib/sparky-stereo-ffmpeg-fdk/{common.sh,check-update,write-pin}   its functions, the apt hook that rebuilds on an update,
#                                                                   and the writer of the pin (the postinst runs it)
#   /usr/share/sparky/sparky-stereo-ffmpeg-fdk/{en,pl,pt_BR}        the strings
#   (not shipped: /etc/apt/preferences.d/sparky-stereo-ffmpeg-fdk is written by each build, exact version at 1002, because apt
#   takes a version pin only exact or with a trailing * and the local version changes with every build)
#   /etc/apt/apt.conf.d/99sparky-stereo-ffmpeg-fdk                  the hook (APT::Update::Post-Invoke-Success)
#   /etc/apt/sources.list.d/sparky-stereo-ffmpeg-src.sources        the edition's source index (deb-src), for the build
# Nothing is built by installing the package: the first run explains, asks, and only then builds.
# CPU_MINUTES is the build's CPU time (user plus system, minutes), measured on the container build of ffmpeg-dmo
# 10:9.0.2-dmo1+stereo3d2 (media-on-dmo, 2026-10-08): the time the command tells the user is this divided by the cores.
# Needs only dpkg-deb.
# Usage: build.sh   (output goes to $OUT, default ${SPARKY_REPO_DIR})
# Last update 2026/10/29
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
VERSION=${VERSION:-20261029~sparky9~0+lc1}
CPU_MINUTES=${CPU_MINUTES:-35}
PKG=sparky-stereo-ffmpeg-fdk
W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/fdk-build.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/usr/lib/$PKG" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" \
	"$D/etc/apt/apt.conf.d" "$D/etc/apt/sources.list.d"

install -m 755 "$HERE/bin/$PKG" "$D/usr/bin/$PKG"
install -m 644 "$HERE/lib/common.sh" "$D/usr/lib/$PKG/common.sh"
install -m 755 "$HERE/lib/check-update" "$D/usr/lib/$PKG/check-update"
install -m 755 "$HERE/lib/write-pin" "$D/usr/lib/$PKG/write-pin"
sed -i "s/@CPU_MINUTES@/$CPU_MINUTES/" "$D/usr/lib/$PKG/common.sh"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE/apt/99sparky-stereo-ffmpeg-fdk" "$D/etc/apt/apt.conf.d/99sparky-stereo-ffmpeg-fdk"
install -m 644 "$HERE/apt/sparky-stereo-ffmpeg-src.sources" "$D/etc/apt/sources.list.d/sparky-stereo-ffmpeg-src.sources"
printf '%s\n' /etc/apt/apt.conf.d/99sparky-stereo-ffmpeg-fdk /etc/apt/sources.list.d/sparky-stereo-ffmpeg-src.sources \
	>"$D/DEBIAN/conffiles"

cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
case "$1" in
configure)
	# installed again while the FFmpeg built here is still on the computer: apt keeps it again
	if [ -x /usr/lib/sparky-stereo-ffmpeg-fdk/write-pin ]; then
		/usr/lib/sparky-stereo-ffmpeg-fdk/write-pin || true
	fi
	;;
esac
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst"

cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
case "$1" in
remove | purge)
	# the pin goes with the package; the local build stays installed and, without the pin, apt puts the edition's FFmpeg back
	# at the next full-upgrade
	if [ "$1" = remove ] && [ -s /var/lib/sparky-stereo-ffmpeg-fdk/installed ]; then
		echo "sparky-stereo-ffmpeg-fdk: the FFmpeg built here is still installed; the next full-upgrade puts the edition's FFmpeg back."
		echo "To go back right away, install this package again and run: sparky-stereo-ffmpeg-fdk --remove"
	fi
	rm -f /etc/apt/preferences.d/sparky-stereo-ffmpeg-fdk
	;;
esac
case "$1" in
purge)
	rm -rf /var/lib/sparky-stereo-ffmpeg-fdk /var/log/sparky-stereo-ffmpeg-fdk.log
	;;
esac
exit 0
EOS
chmod 755 "$D/DEBIAN/postrm"

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

Note: this package contains no part of Fraunhofer's AAC encoder. It builds FFmpeg on the user's own computer with it
(libfdk-aac, installed from the user's own apt sources); the result is for that computer only (FFmpeg's LICENSE.md).
EOS
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
gzip -9n -c "$HERE/CHANGELOG" >"$D/usr/share/doc/$PKG/changelog.gz"
chmod 644 "$D/usr/share/doc/$PKG/changelog.gz" "$D/usr/share/doc/$PKG/copyright"
find "$D" -type d -exec chmod 755 {} +

SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: sparky-stereo-apt, apt, dpkg-dev, build-essential, fakeroot, python3, sudo | pkexec
Recommends: powermgmt-base
Section: sound
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: FFmpeg with Fraunhofer's AAC encoder, built on your own computer
 Sparky Stereo OS ships FFmpeg without Fraunhofer's AAC encoder (libfdk_aac):
 FFmpeg's licence does not allow passing on a build that includes it. This
 helper builds the edition's FFmpeg on your computer with the encoder and
 installs it as a local version that apt keeps, and builds it again by itself
 when the edition updates FFmpeg. The result is for that computer only. Nothing
 is built until you run sparky-stereo-ffmpeg-fdk, which says so first and asks.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort |
	grep -v -x -F -f <(sed 's|^/||' DEBIAN/conffiles) | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone \
    "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
