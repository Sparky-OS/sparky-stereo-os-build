#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 39: builds dolphin-emu 2609.b+dfsg-1+stereo3d1+lc1 from Debian's 2609.b+dfsg-1 source package:
# the source package once (the two patches of patches/, overlay.py, the changelog), then the Lean Code source, then the
# build with the link and start gate against Debian's own build, then lean.release check-debs (the build record).
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR IMAGE
#   PREVIOUS_DIR: Debian's dolphin-emu 2609.b+dfsg-1 .deb files (the predecessor); SOURCE_DIR: Debian's .dsc, debian.tar.xz
#   and orig tarball; IMAGE: a debian:testing image with dpkg-dev, devscripts, debhelper, python3, clang, nodejs,
#   node-acorn, perl and python3-yaml. SPARKY_REPO_DIR: the edition's published tree; SPARKY_LC_ARCHIVE_DIR: the link
#   gate's folder (sources.json and the public keyrings it names, sparky-os/lean/archive.md). BUILD_NAME names the container.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
: "${SPARKY_REPO_DIR:?the edition's published tree}" "${SPARKY_LC_ARCHIVE_DIR:?the link gate's folder, see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
IMAGE=$4
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
name=${BUILD_NAME:-dolphin-emu-build-$$}
sparky_provenance_init "$IMAGE"
docker run -d --name "$name" --pull=never --ulimit core=1 --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$WORK":/work -v "$SRC":/src:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1' >/dev/null
while [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ]; do sleep 10; done
status=$(docker inspect -f '{{.State.ExitCode}}' "$name")
docker rm "$name" >/dev/null
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/build.log" >&2; exit 1; }
