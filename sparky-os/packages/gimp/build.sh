#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds gimp 3.2.8-1+stereo3d3+lc1 (queue row 137, the stereo GIMP's milestone 3, the deep and HDR
# canvas; milestone 1's +stereo3d1 was made by make-source.sh from Debian's 3.2.8-1, milestone 2's +stereo3d2 by
# make-source-2.sh): make-source-3.sh, the successor of +stereo3d2, then release/build-from-lc-dsc.sh with the Lean Code
# link and start gate. The gate's archive list is
# this folder's archive-sources.json (Debian testing, deb-multimedia, the edition's tree) unless SPARKY_LC_ARCHIVE_DIR
# names one.
#   build.sh WORK PREVIOUS SIBLINGS REPO [IMAGE]
#   WORK           an empty folder: source/ (the .dsc and its files) and out/ (packages, buildinfo, changes, build record)
#   PREVIOUS       a folder with the +stereo3d2+lc1 source package (checked against source-stereo3d2.sha256)
#   SIBLINGS       a folder of the packages GIMP needs that the repository has not published yet: gtk+3.0
#                  3.24.52-3+stereo3d2+lc1 (libgtk-3-0t64, libgtk-3-common, libgtk-3-dev, gir1.2-gtk-3.0, ...) and
#                  stereo-layer 1.24.0-1+lc1 (libstereo-policy1, libstereo-policy-dev); empty once a round carries them
#   REPO           the edition's repository, mounted read-only
#   IMAGE          the build image (default sparky-lc-migration:20261020)
# GIMP's own test suite is not run in this build (nocheck): the lane's proof runs it on the tree before and after the
# patches. The earlier build to compare with is the staged +stereo3d2+lc1.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -ge 4 ] || { sed -n '/^#   build.sh/,/^# patches. There/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) SRC=$(realpath "$2") SIB=$(realpath "$3") REPO=$(realpath "$4") IMG=${5:-sparky-lc-migration:20261020}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
if [ -z "${SPARKY_LC_ARCHIVE_DIR:-}" ]; then
	SPARKY_LC_ARCHIVE_DIR=$WORK/archive
	mkdir -p "$SPARKY_LC_ARCHIVE_DIR"
	cp "$HERE/archive-sources.json" "$SPARKY_LC_ARCHIVE_DIR/sources.json"
	cp /usr/share/keyrings/debian-archive-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp "$SPARKY_LC_ARCHIVE_DIR/"
	cp "$REPO/sparky-stereo-repo.asc" "$SPARKY_LC_ARCHIVE_DIR/"
fi
export SPARKY_LC_ARCHIVE_DIR
bash "$HERE/make-source-3.sh" "$SRC" "$WORK/source" "$IMG"
if [ -n "$(find "$SIB" -maxdepth 1 -name '*.deb' | head -1)" ]; then
	export SPARKY_LC_SIBLINGS_DIR=$SIB SPARKY_LC_INSTALL_SIBLINGS=1
fi
SPARKY_DEB_BUILD_OPTIONS=${SPARKY_DEB_BUILD_OPTIONS:-nocheck} \
	bash "$TOP/release/build-from-lc-dsc.sh" "$WORK/source/gimp_3.2.8-1+stereo3d3+lc1.dsc" amd64 "$IMG" "$REPO" "$WORK/out"
