#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: dmemcg-booster from upstream's tag (gitlab.steamos.cloud/holo/dmemcg-booster), the commit checked,
# through the Lean Code toolkit, in a throwaway Debian testing container with the edition's repository pinned at 1001.
# Usage: build.sh [out-dir]   (default ${SPARKY_STAGING_DIR}/dmemcg-booster; REPO, default /var/tmp/sparky-repo-current)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-${SPARKY_STAGING_DIR:?}/dmemcg-booster}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
TAG=0.1.3
COMMIT=4305d7438ca81a5854fc1f62ead89eedd9fc0f0f
DEBV=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
UPV=${DEBV%-*}
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/dmemcg-booster.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
git clone -q --branch "$TAG" https://gitlab.steamos.cloud/holo/dmemcg-booster.git "$WORK/up"
[ "$(git -C "$WORK/up" rev-parse HEAD)" = "$COMMIT" ] || { echo "tag $TAG is not $COMMIT" >&2; exit 1; }
git -C "$WORK/up" archive --format=tar --prefix="dmemcg-booster-$UPV/" "$COMMIT" | xz -6 > "$WORK/dmemcg-booster_$UPV.orig.tar.xz"
tar -xJf "$WORK/dmemcg-booster_$UPV.orig.tar.xz" -C "$WORK"
cp -a "$HERE/debian" "$WORK/dmemcg-booster-$UPV/"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "dmemcg-booster-$UPV" "$DEBV+lc1" "$REPO"
mkdir -p "$OUT"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
