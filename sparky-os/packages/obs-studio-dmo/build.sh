#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# OBS Studio as the edition's: deb-multimedia's obs-studio-dmo source with the patches in patches/ (the canvas's stereo
# layout in libobs, and the encoders and muxers writing the 3D marks from it), built with Lean Code and its link gate.
# Usage: OUT=DIR SRC=DIR IMAGE=BUILDER SCRATCH=DIR SPARKY_LC_ARCHIVE_DIR=DIR REPO=PUBLISHED_TREE [SIBLINGS_DIR=DIR SIBLINGS=FILE] bash build.sh
#   SRC holds deb-multimedia's obs-studio-dmo_33.0.1-dmo2.dsc and its tarballs (apt-get source --download-only obs-studio-dmo);
#   IMAGE carries `apt-get build-dep obs-studio-dmo` with the edition's FFmpeg at its pin, and libstereo-av-dev (patch 0011);
#   SIBLINGS names, for the link gate, the edition's packages the build needs that are newer than the published tree
#   (libstereo-av1 1.23 for media playback), as paths under SIBLINGS_DIR mounted at /siblings.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
. "$HERE/../../repo/build-provenance.sh"
OUT=${OUT:?} SRC=${SRC:?} IMAGE=${IMAGE:?} SCRATCH=${SCRATCH:?}
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive: see sparky-os/lean/archive.md}"
REPO=${REPO:?the published tree of the edition, mounted read-only at /repo}
SIBLINGS_DIR=${SIBLINGS_DIR:-$SCRATCH/no-siblings}
mkdir -p "$OUT" "$SCRATCH" "$SIBLINGS_DIR"
sibling_args=()
if [ -n "${SIBLINGS:-}" ]; then
	sibling_args=(-e SPARKY_LC_SIBLINGS_FILE=/archive-siblings.txt -v "$SIBLINGS":/archive-siblings.txt:ro)
fi
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --pull=never --ulimit core=1 --cpus 4 --user "$(id -u):$(id -g)" -e HOME="$SCRATCH/home" -e OUT="$OUT" \
	-e DEB_BUILD_OPTIONS=parallel=4 -e JOBS=4 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH="$SCRATCH/link" \
	"${sibling_args[@]}" -v "$SIBLINGS_DIR":/siblings:ro \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$REPO":/repo:ro -v "$SRC":/src:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro \
	-v "$TREE":"$TREE" -v "$OUT":"$OUT" -v "$SCRATCH":"$SCRATCH" -v /etc/passwd:/etc/passwd:ro \
	"$IMAGE" sh -c "mkdir -p $SCRATCH/home $SCRATCH/link; git config --global --add safe.directory '*'; bash '$HERE/inner.sh'"
