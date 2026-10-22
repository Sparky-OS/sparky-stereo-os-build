#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Builds the transitional packages of the old "extra" FFmpeg libraries, for amd64 and i386: libavcodec-extra63,
# libavformat-extra63, libavfilter-extra12 and the metapackages libavcodec-extra, libavformat-extra, libavfilter-extra.
# Our FFmpeg of 2026-10-02 to 2026-10-07 was built on Debian's packaging, which has separate "extra" libraries with the
# non-free-ish codecs (Conflicts and Provides: libavcodec63 ...). The edition's FFmpeg is built on deb-multimedia's
# packaging now (ffmpeg-dmo), where every codec is in libavcodec63 and there are no "extra" packages. A computer that
# has the old ones installed would be held back by apt (it wants to remove them to install libavcodec63). These
# packages have the same names, a higher version (epoch 10, above the old 7:) and depend on the normal libraries, so
# a full-upgrade replaces the old ones and installs libavcodec63 and the other libraries. They carry no files but the
# documentation, and can be removed once nobody has the old ones. Dependencies are ">= 10:9.0.2" (the upstream version),
# so they stay right when the edition's FFmpeg moves on and when sparky-stereo-ffmpeg-fdk relabels the versions.
# Needs the edition's Lean Code release toolkit and its parser dependencies.
# Usage: build.sh   (output goes to $OUT, default ${SPARKY_REPO_DIR})
# Last update 2026/10/08
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=${LEAN_TOOLKIT:-$HERE/../..}
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
VERSION=${VERSION:-10:9.0.2-dmo1+stereo3d3+lc1}
ARCHES=${ARCHES:-"amd64 i386"}
MIN=10:9.0.2
W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/transitional-build.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
mkdir -p "$OUT"

# package, what it is now, kind
LIST="libavcodec-extra63:libavcodec63:lib
libavformat-extra63:libavformat63:lib
libavfilter-extra12:libavfilter12:lib
libavcodec-extra:libavcodec63:meta
libavformat-extra:libavformat63:meta
libavfilter-extra:libavfilter12:meta"

for arch in $ARCHES; do
	while IFS=: read -r pkg now kind; do
		D=$W/$pkg-$arch
		mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$pkg"
		cat >"$D/usr/share/doc/$pkg/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

On Debian systems, the complete text of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-3'.
EOS
		gzip -9n -c >"$D/usr/share/doc/$pkg/changelog.Debian.gz" <<EOS
$pkg ($VERSION) unstable; urgency=medium

  * Transitional package: $pkg is $now now, built on
    deb-multimedia's packaging, where every codec is in the normal library.
    This package has the old name and a higher version so that an upgrade
    replaces the old "extra" library and installs $now.
    It can be removed.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 08 Oct 2026 12:00:00 +0000
EOS
		chmod 644 "$D/usr/share/doc/$pkg/"*
		find "$D" -type d -exec chmod 755 {} +
		SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
		SECTION=oldlibs
		cat >"$D/DEBIAN/control" <<EOS
Package: $pkg
Source: sparky-stereo-ffmpeg-transitional
Version: $VERSION
Architecture: $arch
Multi-Arch: same
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $now (>= $MIN)
Section: $SECTION
Priority: optional
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues
Description: transitional package, $pkg is $now now
 The edition's FFmpeg is built on deb-multimedia's packaging, where every
 codec is in the normal library and there are no separate "extra" libraries.
 This empty package lets an upgrade replace the old $pkg
 with $now. It can be removed.
EOS
		(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
		bash "$KIT/repo/provenance.sh" --tree "$D"
		PYTHONPATH="$KIT${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
		echo "built $OUT/${pkg}_${VERSION#*:}_${arch}.deb"
	done <<<"$LIST"
done
