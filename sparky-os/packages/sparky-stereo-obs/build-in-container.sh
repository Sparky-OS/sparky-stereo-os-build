#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# The host side of the build: the facts only the host knows go into the container (build-provenance.sh).
# Usage: OUT=DIR IMAGE=BUILDER SCRATCH=DIR bash build-in-container.sh
# The builder image carries debian/control's Build-Depends: deb-multimedia's libobs-dev for the OBS the edition installs, and
# the edition's libstereo-policy-dev 1.23 or newer (the shared input list for C programs).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
. "$HERE/../../repo/build-provenance.sh"
OUT=${OUT:?Set OUT to the workspace output directory}
IMAGE=${IMAGE:?a builder image with the packages named in debian/control}
SCRATCH=${SCRATCH:?a folder with room for the build}
mkdir -p "$OUT" "$SCRATCH"
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --ulimit core=1 --cpus 4 --network none --user "$(id -u):$(id -g)" -e HOME="$SCRATCH/home" -e OUT="$OUT" -e JOBS=4 \
	"${SPARKY_PROV_ARGS[@]}" -v "$TREE":"$TREE" -v "$OUT":"$OUT" -v "$SCRATCH":"$SCRATCH" -v /etc/passwd:/etc/passwd:ro \
	"$IMAGE" sh -c "mkdir -p $SCRATCH/home; git config --global --add safe.directory '*'; cd '$HERE' && bash ./build.sh"
