#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# The host side of the build: the facts only the host knows go into the container (build-provenance.sh), and the link gate gets
# its archive folder (sources.json with Debian, deb-multimedia, whose OBS this module loads into, and the edition's published
# tree as file:/repo, with their keyrings) and the edition's packages the module needs that are newer than the published tree.
# Usage: OUT=DIR SPARKY_LC_ARCHIVE_DIR=DIR REPO=PUBLISHED_TREE IMAGE=BUILDER SCRATCH=DIR [SIBLINGS_DIR=DIR SIBLINGS=FILE] \
#        bash build-in-container.sh
# The builder image carries debian/control's Build-Depends: the edition's libobs-dev (obs-studio-dmo rebuilt as +stereo3d1,
# sparky-os/packages/obs-studio-dmo) and libstereo-layer-dev 1.23 or newer; SIBLINGS names those debs for the link gate
# while the published tree lacks them.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
. "$HERE/../../repo/build-provenance.sh"
OUT=${OUT:?Set OUT to the workspace output directory}
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive: see sparky-os/lean/archive.md}"
REPO=${REPO:?the published tree of the edition, mounted read-only at /repo}
IMAGE=${IMAGE:?a builder image with the packages named in debian/control}
SCRATCH=${SCRATCH:?a folder with room for the link gate}
SIBLINGS_DIR=${SIBLINGS_DIR:-$SCRATCH/no-siblings}
mkdir -p "$OUT" "$SCRATCH" "$SIBLINGS_DIR"
sibling_args=()
if [ -n "${SIBLINGS:-}" ]; then
	sibling_args=(-e SPARKY_LC_SIBLINGS_FILE=/archive-siblings.txt -v "$SIBLINGS":/archive-siblings.txt:ro)
fi
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --pull=never --ulimit core=1 --cpus 4 --user "$(id -u):$(id -g)" -e HOME="$SCRATCH/home" -e OUT="$OUT" -e JOBS=4 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH="$SCRATCH/link" \
	"${sibling_args[@]}" -v "$SIBLINGS_DIR":/siblings:ro \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$REPO":/repo:ro -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro \
	-v "$TREE":"$TREE" -v "$OUT":"$OUT" -v "$SCRATCH":"$SCRATCH" -v /etc/passwd:/etc/passwd:ro \
	"$IMAGE" sh -c "mkdir -p $SCRATCH/home $SCRATCH/link; git config --global --add safe.directory '*'; cd '$HERE' && bash ./build.sh"
