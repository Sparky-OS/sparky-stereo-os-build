#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Ports our patches and packaging changes to a deb-multimedia source package: the first step of every new release of
# ffmpeg-dmo or mpv-dmo (see ../README.md). From deb-multimedia's own source package it makes ours:
#   - unpacks it without applying its patches,
#   - adds our patches (../<package>/patches, their names in series) after its own in debian/patches/series,
#   - applies the changes of debian/control and debian/rules (../<package>/packaging.diff),
#   - puts a changelog entry (../<package>/changelog.in) on top, version <dmo version>+stereo3d<REVISION>,
#   - writes the source package (dsc, debian tarball; the orig tarball beside it).
# A patch that no longer applies stops the script with quilt's message: refresh it by hand (quilt push -f, edit, quilt refresh
# in the unpacked tree, then copy the refreshed patch back into ../<package>/patches).
# Needs dpkg-dev, quilt, patch; run it in a throwaway container (docker/Dockerfile.base has them), as an ordinary user.
# Usage: port.sh ffmpeg|mpv DMO.dsc REVISION OUTDIR [FFMPEG_VERSION]
#   DMO.dsc          deb-multimedia's source package, with its tarballs beside it (apt-get source --download-only ffmpeg-dmo)
#   REVISION         the number after +stereo3d (1 for the first build on this dmo version)
#   OUTDIR           where the source package goes
#   FFMPEG_VERSION   mpv only: the ffmpeg-dmo version (ours) it is built against, for the changelog
#   SOURCE_DATE      the date of the changelog entry (RFC 5322, default now)
# Last update 2026/10/08
set -euo pipefail
pkg=${1:?package: ffmpeg or mpv}
dsc=$(readlink -f "${2:?the .dsc of the deb-multimedia source package}")
rev=${3:?revision}
out=${4:?output folder}
ffv=${5:-}
HERE=$(cd "$(dirname "$0")" && pwd)
M=$HERE/../$pkg
case $pkg in ffmpeg | mpv) ;; *) echo "package: ffmpeg or mpv" >&2; exit 2 ;; esac
dmover=$(sed -n 's/^Version: //p' "$dsc")
version=$dmover+stereo3d$rev
W=$(mktemp -d "${TMPDIR:-/tmp}/port-$pkg.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
mkdir -p "$out"
# the files the .dsc names (orig tarball with its signature if there is one, debian tarball), beside it
for f in $(awk '/^Files:/ {f=1; next} f && /^ / {print $3; next} {f=0}' "$dsc"); do
	for g in "$f" "$f.asc"; do
		[ -f "$(dirname "$dsc")/$g" ] && cp "$(dirname "$dsc")/$g" "$W/"
	done
done
cp "$dsc" "$W/"
cd "$W"
dpkg-source --no-check --no-preparation -x "$(basename "$dsc")" tree >/dev/null
cd tree
mkdir -p debian/patches
[ -f debian/patches/series ] && [ -n "$(tail -c1 debian/patches/series)" ] && echo >>debian/patches/series
cp "$M"/patches/*.patch debian/patches/
cat "$M/patches/series" >>debian/patches/series
patch -p1 --no-backup-if-mismatch <"$M/packaging.diff" >/dev/null
sed -e "s|@VERSION@|$version|" -e "s|@DMOVERSION@|$dmover|" -e "s|@FFMPEG@|$ffv|" -e "s|@DATE@|${SOURCE_DATE:-$(date -R)}|" "$M/changelog.in" | cat - debian/changelog >debian/changelog.new
mv debian/changelog.new debian/changelog
# the patches must apply in order (quilt says which one does not)
QUILT_PATCHES=debian/patches quilt --quiltrc=/dev/null push -a >/dev/null
QUILT_PATCHES=debian/patches quilt --quiltrc=/dev/null pop -a >/dev/null
rm -rf .pc
dpkg-source --before-build . >/dev/null
cd ..
dpkg-source -b tree 2>&1 | grep -v -E 'signature|because|warning' || true
(cd tree && dpkg-source --after-build . >/dev/null)
cp ./*"${version#*:}".dsc ./*"${version#*:}".debian.tar.* ./*.orig.tar.* "$out/"
echo "$pkg $version: $(ls "$out"/*"${version#*:}".dsc)"
