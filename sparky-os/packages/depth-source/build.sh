#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds qt6-multimedia 6.11.2-3+stereo3d14+lc1 or dragon 4:26.04.0-1+stereo3d6+lc1 (depth as a 3D source,
# ORDER 151 step R part 2, group 2) from the source next-source.sh made, through Lean Code (build-in-container.sh): the debs
# are built from the +lc1 source with the link and start gate against the earlier +lc1 build, then lean.release check-debs.
# Usage: build.sh PACKAGE WORK SOURCE_DIR PREVIOUS_DIR REPO_DIR ARCHIVE_DIR [NEW_DIR]
#   SOURCE_DIR: the folder next-source.sh wrote (the new .dsc and Debian tarball) with the orig tarball beside them
#   PREVIOUS_DIR: the published +lc1 .deb files of the package, for the link gate
#   REPO_DIR: the signed published tree the build dependencies come from (read only)
#   ARCHIVE_DIR: the link gate's folder, mounted at /archive: sources.json and keyrings/ (sparky-os/lean/archive.md)
#   NEW_DIR: a flat repository (Packages, Release) of debs built earlier in the round (dragon needs qt6-multimedia's)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$1
WORK=$(mkdir -p "$2" && cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
PREV=$(cd "$4" && pwd)
REPO=$(cd "$5" && pwd)
ARCHIVE=$(cd "$6" && pwd)
NEW=${7:+$(cd "$7" && pwd)}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
mkdir -p "$WORK/home"
docker run --rm --name "d151-build-$PKG" --cpus "${THREADS:-6}" --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e PKG="$PKG" -e THREADS="${THREADS:-6}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$ARCHIVE":/archive:ro -v "$WORK":/work -v "$SRC":/src:ro -v "$REPO":/repo:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro ${NEW:+-v "$NEW":/new:ro} \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	--entrypoint bash sparky-lc-migration:20261020 -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1'
