#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: plasma-foreground-booster from Natalie Vock's kcgroups fork (github.com/pixelcluster/kcgroups, branch dmemcg-foreground-booster), the commit checked,
# through the Lean Code toolkit, in a throwaway Debian testing container with the edition's repository pinned at 1001.
# Usage: build.sh [out-dir]   (default ${SPARKY_STAGING_DIR}/plasma-foreground-booster; REPO, default /var/tmp/sparky-repo-current;
#        EXTRA, a folder holding libkf5cgroups-dev while the repository does not carry it yet)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-${SPARKY_STAGING_DIR:?}/plasma-foreground-booster}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
BRANCH=dmemcg-foreground-booster
COMMIT=0553351dd13af58dcfccff52c930cc9bf719d928
DEBV=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
UPV=${DEBV%-*}
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/plasma-foreground-booster.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
git clone -q --branch "$BRANCH" https://github.com/pixelcluster/kcgroups.git "$WORK/up"
git -C "$WORK/up" merge-base --is-ancestor "$COMMIT" HEAD || { echo "$COMMIT is not on $BRANCH" >&2; exit 1; }
git -C "$WORK/up" archive --format=tar --prefix="plasma-foreground-booster-$UPV/" "$COMMIT" | xz -6 > "$WORK/plasma-foreground-booster_$UPV.orig.tar.xz"
tar -xJf "$WORK/plasma-foreground-booster_$UPV.orig.tar.xz" -C "$WORK"
cp -a "$HERE/debian" "$WORK/plasma-foreground-booster-$UPV/"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "plasma-foreground-booster-$UPV" "$DEBV+lc1" "$REPO"
mkdir -p "$OUT"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
