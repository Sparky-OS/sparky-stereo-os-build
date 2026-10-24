#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
: "${DOCKER_HOST:?Set the granted Docker endpoint}"
: "${SPARKY_PACKAGE_WORK:?Set owned package scratch}"
: "${SPARKY_PUBLISHED_TREE:?Set the signed predecessor repository}"
: "${SPARKY_RELEASE_TOOLKIT:?Set the release machinery snapshot}"
: "${SPARKY_LIBPLACEBO_INPUT:?Set the retained multimedia source directory}"
: "${SPARKY_PACKAGE_IMAGE:?Set the freshly updated build image}"
: "${SPARKY_TEST_PREFIX:?Set an owned container prefix}"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
here=$(cd "$(dirname "$0")" && pwd)
packages=$(cd "$here/../.." && pwd)
pkg=$1
suffix=${2:-}
work=$SPARKY_PACKAGE_WORK/jobs/$pkg$suffix
mkdir -p "$SPARKY_PACKAGE_WORK/out/$pkg" "$work" "$SPARKY_PACKAGE_WORK/previous" "$SPARKY_PACKAGE_WORK/new" "$SPARKY_PACKAGE_WORK/logs"
name=$SPARKY_TEST_PREFIX-package-$pkg$suffix
entry=build-in-container.sh
[ "$pkg" != sparky-stereo-hardware ] || entry=build-hardware.sh
cp "$here/$entry" "$work/build-entry.sh"
printf '%s\n' "$name" >> "${SPARKY_ARTIFACTS:?Set the lane artifact record}"
docker run --platform linux/amd64 --cpus 4 --name "$name" -e PKG="$pkg" -e SOURCE_DSC="${SOURCE_DSC:-}" -e BINARY_ONLY="${BINARY_ONLY:-}" \
 -v "$work:/work" -v "$SPARKY_PUBLISHED_TREE:/pub:ro" \
 -v "$SPARKY_PACKAGE_WORK/new:/new:ro" -v "$SPARKY_PACKAGE_WORK/previous:/previous:ro" \
 -v "$SPARKY_PACKAGE_WORK/out/$pkg:/candidate:ro" -v "$packages:/kit:ro" -v "$SPARKY_RELEASE_TOOLKIT:/toolkit:ro" \
 -v "$SPARKY_LIBPLACEBO_INPUT:/libplacebo-input:ro" \
 -v "${SPARKY_DMO_KEYRING:?Set the public multimedia keyring}:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro" \
 "$SPARKY_PACKAGE_IMAGE" bash /work/build-entry.sh \
 > "$SPARKY_PACKAGE_WORK/logs/$pkg-container.log" 2>&1
