#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-beep, Daniel's and Paweł's PC speaker notifier for the Server Edition
# (github.com/Sparky-OS/sparky-beep), as a Debian source and binary package in a fresh
# debian:testing container, from a clone given as SRC (default: the Sparky-OS clone in
# /K3D/GitHub). The package keeps the program's own debian/ (dh 13, 3.0 (native)); this
# script only provides the Forky build room, 4 threads, and copies the results to OUT.
# Last update 2026/10/14
set -euo pipefail
SRC=${SRC:-/K3D/GitHub/sparky-beep}
OUT=${OUT:-/K3D/temp/sparky-os/repo}
IMAGE=${IMAGE:-debian:testing}
VERSION=$(sed -n '1s/^sparky-beep (\([^)]*\)).*/\1/p' "$SRC/debian/changelog")
W=$(mktemp -d /K3D/temp/sparky-os/beep-build.XXXXXX)
trap 'chmod -R u+w "$W"; rm -rf "$W"' EXIT
mkdir -p "$W/sparky-beep-$VERSION"
tar -C "$SRC" --exclude=.git --exclude=bin/tbeep -cf - . | tar -C "$W/sparky-beep-$VERSION" -xf -
docker run --rm --platform linux/amd64 --cpus 4 --user "$(id -u):$(id -g)" -e HOME="$W" -e DEBIAN_FRONTEND=noninteractive \
	-e DEB_BUILD_OPTIONS=parallel=4 -v "$W:$W" -w "$W/sparky-beep-$VERSION" "$IMAGE" bash -c '
	apt-get update -qq >/dev/null 2>&1 || true
	# a user cannot apt-get install; the image must carry debhelper, dpkg-dev and gcc (see README.md)
	dpkg-buildpackage -us -uc --no-sign -j4'
mkdir -p "$OUT" "$OUT/source"
cp "$W"/sparky-beep_"$VERSION"_amd64.deb "$OUT/"
cp "$W"/sparky-beep_"$VERSION".dsc "$W"/sparky-beep_"$VERSION".tar.xz "$OUT/source/"
echo "built $OUT/sparky-beep_${VERSION}_amd64.deb (source in $OUT/source)"
