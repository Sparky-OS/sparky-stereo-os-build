#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: dkms 3.4.4 on Debian's packaging, through the Lean Code toolkit, in a throwaway Debian testing container
# with the edition's repository pinned at 1001 (release/build-dh-lean.sh).
# debian/ is Debian's packaging as Viorel Cernateanu's merge request !8 has it (salsa.debian.org/debian/dkms, commit
# 03eded2e), with our changelog entry; the upstream tree is dkms-project's tag v3.4.4, its commit and tree checked (the
# tree equals the GitHub release tarball Debian's pristine-tar records). The orig tarball is the tag's git archive, xz,
# as the edition's other upstream builds make it.
# Usage: build.sh [out-dir]   (default ${SPARKY_STAGING_DIR}/dkms; REPO, default /var/tmp/sparky-repo-current)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
# Last update 2026/11/01
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-${SPARKY_STAGING_DIR:?}/dkms}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
TAG=v3.4.4
COMMIT=cb2790f3d900598d5e55865540f45a049a696e66
TREE=acfb0ae90df39ecdf90b083183c1f3bc489da3b8
DEBV=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
UPV=${DEBV%-*}
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/dkms.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
git clone -q --depth 1 --branch "$TAG" https://github.com/dkms-project/dkms.git "$WORK/up"
[ "$(git -C "$WORK/up" rev-parse HEAD)" = "$COMMIT" ] || { echo "tag $TAG is not $COMMIT" >&2; exit 1; }
[ "$(git -C "$WORK/up" rev-parse 'HEAD^{tree}')" = "$TREE" ] || { echo "tag $TAG's tree is not $TREE" >&2; exit 1; }
git -C "$WORK/up" archive --format=tar --prefix="dkms-$UPV/" "$COMMIT" | xz -6 > "$WORK/dkms_$UPV.orig.tar.xz"
tar -xJf "$WORK/dkms_$UPV.orig.tar.xz" -C "$WORK"
cp -a "$HERE/debian" "$WORK/dkms-$UPV/"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "dkms-$UPV" "$DEBV+lc1" "$REPO"
mkdir -p "$OUT"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
