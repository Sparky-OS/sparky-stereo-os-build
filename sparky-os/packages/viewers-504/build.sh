#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/10
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 504: build.sh PKG OLD NEW PATCH ITEM STAGE_DIR PUBLISHED_TREE OUT ARCHIVE_DIR SIBLINGS_FILE
#   ARCHIVE_DIR is the link gate's folder (sources.json, keyrings/), SIBLINGS_FILE the published edition's .deb paths as the container sees them (/repo/pool/...)
#   gwenview  4:26.04.0-1+stereo3d8 4:26.04.0-1+stereo3d9 stereo-opaque-picture-background.patch "text"
#   kio-extras 4:26.04.0-1+stereo3d4 4:26.04.0-1+stereo3d5 kio-extras-thumbnailer-versions.patch "text"
# STAGE_DIR holds folders of staged debs (stereo-layer 1.17.3-1+lc1), PUBLISHED_TREE is the signed tree (read only); OUT is empty.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
PKG=$1 OLD=$2 NEW=$3 PATCH=$4 ITEM=$5
STAGE=$(cd "$6" && pwd) TREE=$(cd "$7" && pwd) OUT=$(mkdir -p "$8" && cd "$8" && pwd) ARCHIVE=$(cd "$9" && pwd) SIBS=$(readlink -f "${10}")
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
sparky_provenance_init sparky-lc-migration:20261020
# the candidate side supplies the edition without this package's own earlier binaries, and with the staged debs (/stage)
grep -v "/pool/main/./$PKG/" "$SIBS" > "$OUT/siblings-current.txt" || true
for d in "$STAGE"/*/*.deb; do case $d in *-dbgsym_*|*-lc-hr_*) ;; *) echo "/stage/$(basename "$(dirname "$d")")/$(basename "$d")" >> "$OUT/siblings-current.txt" ;; esac; done
IN=$OUT/in; mkdir -p "$IN"
for f in "$TREE"/pool/main/${PKG:0:1}/$PKG/"$PKG"_*"${OLD#*:}"+lc1.dsc "$TREE"/pool/main/${PKG:0:1}/$PKG/"$PKG"_*"${OLD#*:}"+lc1.debian.tar.xz "$TREE"/pool/main/${PKG:0:1}/$PKG/"$PKG"_*.orig.tar.*; do cp "$f" "$IN/"; done
PREV=$OUT/prev; mkdir -p "$PREV"; cp "$TREE"/pool/main/${PKG:0:1}/$PKG/*+lc1_amd64.deb "$TREE"/pool/main/${PKG:0:1}/$PKG/*+lc1_all.deb "$PREV/" 2>/dev/null || true
docker run --rm --name "${BUILD_NAME_PREFIX:-view-504-build}-$PKG" --ulimit core=0 --cpus "${THREADS:-4}" --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e PKG="$PKG" -e OLD="${OLD#*:}" -e NEW="$NEW" -e PATCH="$PATCH" -e ITEM="$ITEM" \
	-v "$STAGE":/stage:ro -v "$IN":/in:ro -v "$HERE/patches":/patch:ro -v "$HERE/../..":/toolkit:ro -v "$PREV":/prev:ro -v "$TREE":/repo:ro -v "$OUT":/out \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	-v "$ARCHIVE":/archive:ro -v "$SIBS":/previous-siblings.txt:ro -v "$OUT/siblings-current.txt":/siblings.txt:ro -e SPARKY_LC_SCRATCH=/out/link-scratch -v "$HERE/recipe.sh":/recipe.sh:ro --entrypoint bash sparky-lc-migration:20261020 -c 'bash /recipe.sh' > "$OUT/recipe.log" 2>&1
tail -25 "$OUT/recipe.log"
