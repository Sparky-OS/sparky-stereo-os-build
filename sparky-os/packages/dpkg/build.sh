#!/bin/bash
# Sparky Stereo OS: builds dpkg 1.23.11+stereo3d1+lc1 (dpkg, dpkg-dev, libdpkg-perl, libdpkg-dev, dselect and their
# Lean Code HR companions) from Debian's dpkg 1.23.11 source package, with patches/ (the Lean Code shared-file check and
# its functional test, ORDER 363) and changelog-stereo3d1.txt.
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Usage: build.sh WORK SOURCE_DIR   (SOURCE_DIR: the folder holding Debian's dpkg_1.23.11.dsc and dpkg_1.23.11.tar.xz, as
#   apt-get source downloads them; WORK: a new or empty folder)
# The candidates and their SHA256SUMS land in WORK/out; dpkg's test suites' logs in WORK (build.log, functional.log). Run
# Lean Code's link and start gate (python3 -m lean.release check-link) on WORK/out's archives afterwards.
# Last update 2026/11/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
: "${BUILD_IMAGE:=sparky-lc-migration:20261020}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
name=dpkg-build-$$
docker run -d --name "$name" --cpus 4 --platform linux/amd64 \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	"$BUILD_IMAGE" bash -c 'bash /tools/build-in-container.sh > /work/container.log 2>&1' >/dev/null
status=$(docker wait "$name")
docker rm "$name" >/dev/null
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/container.log" >&2; exit 1; }
mkdir -p "$WORK/out/source"
cp "$WORK"/lc/*+lc1_*.deb "$WORK/out/"
cp "$WORK"/lc/dpkg_1.23.11+stereo3d1+lc1.dsc "$WORK"/lc/dpkg_1.23.11+stereo3d1+lc1.tar.xz "$WORK/out/source/"
(cd "$WORK/out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
