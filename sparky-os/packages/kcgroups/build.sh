#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: kcgroups from Natalie Vock's fork (github.com/pixelcluster/kcgroups, tag kcgroups-dmemcg-experimental), the commit checked,
# through the Lean Code toolkit, in a throwaway Debian testing container with the edition's repository pinned at 1001.
# Usage: build.sh [out-dir]   (default ${SPARKY_STAGING_DIR}/kcgroups; REPO, default /var/tmp/sparky-repo-current)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-${SPARKY_STAGING_DIR:?}/kcgroups}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
TAG=kcgroups-dmemcg-experimental
COMMIT=d106f1c8f44c1f231a9050b2bf82a34bb7d5db32
DEBV=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
UPV=${DEBV%-*}
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/kcgroups.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
git clone -q --branch "$TAG" https://github.com/pixelcluster/kcgroups.git "$WORK/up"
[ "$(git -C "$WORK/up" rev-parse HEAD)" = "$COMMIT" ] || { echo "tag $TAG is not $COMMIT" >&2; exit 1; }
git -C "$WORK/up" archive --format=tar --prefix="kcgroups-$UPV/" "$COMMIT" | xz -6 > "$WORK/kcgroups_$UPV.orig.tar.xz"
tar -xJf "$WORK/kcgroups_$UPV.orig.tar.xz" -C "$WORK"
cp -a "$HERE/debian" "$WORK/kcgroups-$UPV/"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "kcgroups-$UPV" "$DEBV+lc1" "$REPO"
mkdir -p "$OUT"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
