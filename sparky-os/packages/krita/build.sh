#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds krita 1:6.0.4.1+dfsg-1+stereo3d1+lc1 (queue row 148, Krita's milestone 1): make-source.sh
# from Debian's 1:5.3.4.1+dfsg-1, then release/build-from-lc-dsc.sh with the Lean Code link and start gate. The gate's
# archive list is this folder's archive-sources.json (Debian testing, deb-multimedia, the edition's tree) unless
# SPARKY_LC_ARCHIVE_DIR names one. Every package it needs is published (Qt 6.11.2 +stereo3d23, the stereo layer
# 1.22.0, KScreen), so there are no siblings.
#   build.sh WORK DEBIAN_SOURCE REPO [PREVIOUS] [IMAGE]
#   WORK           an empty folder: source/ (the .dsc and its files), out/ (packages, buildinfo, changes, build record)
#   DEBIAN_SOURCE  a folder with Debian's krita_5.3.4.1+dfsg-1 source package (checked against source.sha256)
#   REPO           the edition's repository, mounted read-only
#   PREVIOUS       a folder with the published 1:6.0.4+dfsg-1+stereo3d7+lc1 packages the gate compares with ("" for none)
#   IMAGE          the build image (default sparky-lc-migration:20261020)
# Krita's own test suite is not built (BUILD_TESTING=OFF in Debian's rules, as Debian builds it); the lane's proof runs
# the program from the installed packages.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -ge 3 ] || { sed -n '/^#   build.sh/,/^# Krita.s own/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) SRC=$(realpath "$2") REPO=$(realpath "$3") PREV=${4:-} IMG=${5:-sparky-lc-migration:20261020}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
if [ -z "${SPARKY_LC_ARCHIVE_DIR:-}" ]; then
	SPARKY_LC_ARCHIVE_DIR=$WORK/archive
	mkdir -p "$SPARKY_LC_ARCHIVE_DIR"
	cp "$HERE/archive-sources.json" "$SPARKY_LC_ARCHIVE_DIR/sources.json"
	cp /usr/share/keyrings/debian-archive-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp "$SPARKY_LC_ARCHIVE_DIR/"
	cp "$REPO/sparky-stereo-repo.asc" "$SPARKY_LC_ARCHIVE_DIR/"
fi
export SPARKY_LC_ARCHIVE_DIR
if [ -n "$PREV" ]; then
	export SPARKY_LC_PREVIOUS_DIR=$(realpath "$PREV")
fi
bash "$HERE/make-source.sh" "$SRC" "$WORK/source" "$IMG"
SPARKY_DEB_BUILD_OPTIONS=${SPARKY_DEB_BUILD_OPTIONS:-nocheck} \
	bash "$TOP/release/build-from-lc-dsc.sh" "$WORK/source/krita_6.0.4.1+dfsg-1+stereo3d1+lc1.dsc" amd64 "$IMG" "$REPO" "$WORK/out"
