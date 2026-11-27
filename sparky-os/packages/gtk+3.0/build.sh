#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds gtk+3.0 3.24.52-3+stereo3d2+lc1 (queue row 137, GIMP milestone 3: the deep and HDR canvas;
# +stereo3d1 was made by build-stereo3d1.sh from Debian's 3.24.52-3): make-source-2.sh, the successor of +stereo3d1, then
# release/build-from-lc-dsc.sh with the Lean Code link and start gate, compared with the +stereo3d1 build. The gate's
# archive list is this folder's archive-sources.json (Debian testing, deb-multimedia, the edition's tree) unless
# SPARKY_LC_ARCHIVE_DIR names one.
#   build.sh WORK PREVIOUS REPO [IMAGE]
#   WORK      an empty folder: source/ (the .dsc and its files) and out/ (packages, buildinfo, changes, build record)
#   PREVIOUS  the +stereo3d1+lc1 stage: its source package (checked against source-stereo3d1.sha256) and its binary packages,
#             which the gate compares with
#   REPO      the edition's repository, mounted read-only
#   IMAGE     the build image (default sparky-lc-migration:20261020)
# GTK's own test suite is not run in this build (nocheck): the lane's proof runs it on the tree before and after the
# patches, as Debian's build runs it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -ge 3 ] || { sed -n '/^#   build.sh/,/^# patches, as/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) PREV=$(realpath "$2") REPO=$(realpath "$3") IMG=${4:-sparky-lc-migration:20261020}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
if [ -z "${SPARKY_LC_ARCHIVE_DIR:-}" ]; then
	SPARKY_LC_ARCHIVE_DIR=$WORK/archive
	mkdir -p "$SPARKY_LC_ARCHIVE_DIR"
	cp "$HERE/archive-sources.json" "$SPARKY_LC_ARCHIVE_DIR/sources.json"
	cp /usr/share/keyrings/debian-archive-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp "$SPARKY_LC_ARCHIVE_DIR/"
	cp "$REPO/sparky-stereo-repo.asc" "$SPARKY_LC_ARCHIVE_DIR/"
fi
export SPARKY_LC_ARCHIVE_DIR
bash "$HERE/make-source-2.sh" "$PREV" "$WORK/source" "$IMG"
mkdir -p "$WORK/previous"
find "$PREV" -maxdepth 1 -name '*.deb' ! -name '*-dbgsym_*' -exec cp {} "$WORK/previous/" \;
SPARKY_LC_PREVIOUS_DIR=$WORK/previous SPARKY_DEB_BUILD_OPTIONS=${SPARKY_DEB_BUILD_OPTIONS:-nocheck} \
	bash "$TOP/release/build-from-lc-dsc.sh" "$WORK/source/gtk+3.0_3.24.52-3+stereo3d2+lc1.dsc" amd64 "$IMG" "$REPO" "$WORK/out"
