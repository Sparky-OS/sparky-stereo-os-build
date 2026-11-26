#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds gimp-stereo-pictures 0.2.0+lc1 (queue row 137 with row 148, the stereo GIMP's milestone 1):
# make-source.sh, then release/build-from-lc-dsc.sh with the Lean Code link and start gate. The gate's archive list is
# this folder's archive-sources.json (Debian testing, deb-multimedia, the edition's tree) unless SPARKY_LC_ARCHIVE_DIR
# names one.
#   build.sh WORK PHOTOGIMP_REPO REPO [IMAGE]
#   WORK            an empty folder: source/ (the .dsc and its tarball) and out/ (packages, buildinfo, changes, record)
#   PHOTOGIMP_REPO  a git repository holding the commit of source.pin (a clone of Sparky-OS/PhotoGIMP)
#   REPO            the edition's repository, mounted read-only
#   IMAGE           the build image (default sparky-lc-migration:20261020)
# The plug-in's tests need GIMP and the stereo layer's fixtures, so the build runs none; the proof runs round 1's tests on
# the installed package. The hand-assembled 0.1.0 of round 1 was never published: there is no earlier build to compare.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -ge 3 ] || { sed -n '/^#   build.sh/,/^# the installed/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) PG=$(realpath "$2") REPO=$(realpath "$3") IMG=${4:-sparky-lc-migration:20261020}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
if [ -z "${SPARKY_LC_ARCHIVE_DIR:-}" ]; then
	SPARKY_LC_ARCHIVE_DIR=$WORK/archive
	mkdir -p "$SPARKY_LC_ARCHIVE_DIR"
	cp "$HERE/archive-sources.json" "$SPARKY_LC_ARCHIVE_DIR/sources.json"
	cp /usr/share/keyrings/debian-archive-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp "$SPARKY_LC_ARCHIVE_DIR/"
	cp "$REPO/sparky-stereo-repo.asc" "$SPARKY_LC_ARCHIVE_DIR/"
fi
export SPARKY_LC_ARCHIVE_DIR
bash "$HERE/make-source.sh" "$PG" "$WORK/source" "$IMG"
bash "$TOP/release/build-from-lc-dsc.sh" "$WORK/source/gimp-stereo-pictures_0.2.0+lc1.dsc" amd64 "$IMG" "$REPO" "$WORK/out"
