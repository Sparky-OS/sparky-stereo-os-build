#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds celluloid 0.29-3+stereo3d1+lc1 (queue row 137): make-source.sh, then
# release/build-from-lc-dsc.sh with the Lean Code link and start gate. The gate's archive list is this folder's
# archive-sources.json (Debian testing, deb-multimedia, the edition's tree) unless SPARKY_LC_ARCHIVE_DIR names one.
#   build.sh WORK DEBIAN_SOURCE SIBLINGS REPO [IMAGE]
#   WORK           an empty folder: source/ (the .dsc and its files) and out/ (packages, buildinfo, changes, build record)
#   DEBIAN_SOURCE  a folder with Debian's celluloid 0.29-3 source package
#   SIBLINGS       a folder of the packages Celluloid needs that the repository has not published yet: gtk4
#                  +stereo3d3 (libgtk-4-1, libgtk-4-common, libgtk-4-dev, gir1.2-gtk-4.0, libgtk-4-bin, ...) and mpv-dmo
#                  +stereo3d12 (libmpv2, libmpv-dev); empty once a round carries them
#   REPO           the edition's repository, mounted read-only
#   IMAGE          the build image (default sparky-lc-migration:20261020)
# There is no earlier build to compare with: Celluloid 0.29-3 is Debian's until this one.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -ge 4 ] || { sed -n '/^#   build.sh/,/^# There is/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
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
bash "$HERE/make-source.sh" "$SRC" "$WORK/source" "$IMG"
sib=()
if [ -n "$(find "$SIB" -maxdepth 1 -name '*.deb' | head -1)" ]; then
	export SPARKY_LC_SIBLINGS_DIR=$SIB SPARKY_LC_INSTALL_SIBLINGS=1
fi
bash "$TOP/release/build-from-lc-dsc.sh" "$WORK/source/celluloid_0.29-3+stereo3d1+lc1.dsc" amd64 "$IMG" "$REPO" "$WORK/out"
