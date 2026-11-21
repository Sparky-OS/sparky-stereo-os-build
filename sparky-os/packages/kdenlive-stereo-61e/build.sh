#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# ORDER 61e: builds MLT 7.40.0-1+stereo3d8+lc1 and then Kdenlive 26.08.1-1+stereo3d9+lc1 (amd64) from the sources make-sources.sh
# makes, each with the link and start gate (release/build-from-lc-dsc.sh): MLT's gate compares with the published +stereo3d6, and
# Kdenlive's takes the new MLT as an edition sibling, since its Depends names it.
# Usage: build.sh WORK REPO IMAGE
#   WORK   an empty folder: sources (make-sources.sh's WORK), previous-mlt/, previous-kdenlive/ (the published builds), mlt/, kdenlive/
#   REPO   the published tree (dists/mashtabba and pool/), read only
#   IMAGE  the build image (an amd64 Debian testing image; build-from-lc-dsc.sh installs what it needs)
# SPARKY_LC_ARCHIVE_DIR is required (the link gate's sources.json and keyrings); SPARKY_CONTAINER_PREFIX names the containers.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^# Usage/,/^# SPARKY_LC_ARCHIVE_DIR/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) REPO=$(realpath "$2") IMG=$3
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate folder (sources.json and its keyrings)}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
bash "$HERE/make-sources.sh" "$WORK/sources" "$REPO/pool/main" "$IMG"
# the published builds the gate compares with: copies, never links (a staged or published file must not change)
mkdir -p "$WORK/previous-mlt" "$WORK/previous-kdenlive"
for f in "$REPO"/pool/main/m/mlt/*_7.40.0-1+stereo3d6+lc1_*.deb; do cp "$f" "$WORK/previous-mlt/"; done
# The published libmlt-perl +stereo3d6 depends on perlapi-5.42.3, which Debian testing no longer has (perl 5.44.0-3 there on
# 2026-11-21): it cannot be installed today, so it cannot be the gate's baseline; its successor here is built against
# today's perl. Every other predecessor stays.
rm -f "$WORK"/previous-mlt/libmlt-perl_*.deb "$WORK"/previous-mlt/libmlt-perl-*.deb
for f in "$REPO"/pool/main/k/kdenlive/*_26.08.1-1+stereo3d6+lc1_*.deb; do cp "$f" "$WORK/previous-kdenlive/"; done
SPARKY_LC_PREVIOUS_DIR="$WORK/previous-mlt" bash "$TOP/release/build-from-lc-dsc.sh" \
	"$WORK"/sources/source-mlt/mlt_7.40.0-1+stereo3d8+lc1.dsc amd64 "$IMG" "$REPO" "$WORK/mlt"
SPARKY_LC_PREVIOUS_DIR="$WORK/previous-kdenlive" SPARKY_LC_SIBLINGS_DIR="$WORK/mlt" bash "$TOP/release/build-from-lc-dsc.sh" \
	"$WORK"/sources/source-kdenlive/kdenlive_26.08.1-1+stereo3d9+lc1.dsc amd64 "$IMG" "$REPO" "$WORK/kdenlive"
