#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: HeadsetControl 4.3.0 (Denis Arnst's tool for USB headsets: battery, sidetone, lights, in C++20 with CMake) built from the
# release tag's source through the Lean Code toolkit (release/build-dh-lean.sh): the source package has one upstream tarball made by
# make-orig.sh (pinned by tarball SHA-256, commit and git tree id). debian/ is the tracked one at PACKAGING_COMMIT of CLONE.
# Usage: build.sh OUT CLONE [PACKAGING_COMMIT]   (OUT an empty folder; CLONE the edition's build repository)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
CLONE=$(realpath "${2:?clone of the build repository}")
PACKAGING_COMMIT=$(git -C "$CLONE" rev-parse --verify "${3:-HEAD}^{commit}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
UPV=4.3.0
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
git -C "$CLONE" diff --quiet "$PACKAGING_COMMIT" -- sparky-os/packages/headsetcontrol || { echo "the recipe in $CLONE differs from $PACKAGING_COMMIT: commit first" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/headsetcontrol.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
SRC=headsetcontrol-$UPV
mkdir "$WORK/orig"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}headsetcontrol-orig" --platform linux/amd64 --cpus "${CPUS:-4}" --ulimit core=1 \
	-v "$WORK/orig":/out -v "$HERE":/pkg:ro -e OWNER="$(id -u):$(id -g)" \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install git ca-certificates curl xz-utils python3 >/dev/null
useradd --create-home --uid 1000 builder
chown builder:builder /out
runuser -u builder -- env HOME=/tmp/builder-home bash /pkg/make-orig.sh /out
chown -R "$OWNER" /out'
tar -xJf "$WORK/orig/headsetcontrol_$UPV.orig.tar.xz" -C "$WORK"
cp "$WORK/orig/headsetcontrol_$UPV.orig.tar.xz" "$WORK"/
git -C "$CLONE" archive --format=tar "$PACKAGING_COMMIT" sparky-os/packages/headsetcontrol/debian | tar -x -C "$WORK/$SRC" --strip-components=3
echo "packaging: $PACKAGING_COMMIT"
DEBV=$(dpkg-parsechangelog -l "$WORK/$SRC/debian/changelog" -S Version)
[ "${DEBV%-*}" = "$UPV" ] || { echo "debian/changelog is $DEBV, not $UPV" >&2; exit 1; }
rm -rf "$WORK/orig"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "$SRC" "$DEBV+lc1" "$REPO"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
