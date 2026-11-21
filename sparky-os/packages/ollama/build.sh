#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Ollama 0.40.16+ds from upstream's release build, split by hardware (ollama, ollama-cuda, ollama-rocm).
# make-orig.sh makes the two upstream tarballs from the inputs release.tsv pins (the only step that may read the network, and only
# for an input DOWNLOADS lacks); the package is then built in a container with no network, its payload qualified by Lean Code
# without compilation (prepare-lean.py), checked by lean.release check-debs and lintian.
# Usage: build.sh OUT DOWNLOADS [PACKAGING_COMMIT]   (OUT an empty folder; DOWNLOADS keeps the pinned inputs)
# IMAGE: a Debian testing image with dpkg-dev, debhelper, lintian, python3, python3-yaml, node-acorn, zstd, xz-utils, git and curl.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
DL=$(realpath -m "${2:?downloads folder}")
PACKAGING_COMMIT=$(git -C "$TREE" rev-parse --verify "${3:-HEAD}^{commit}")
IMAGE=${IMAGE:?a build image}
UPV=0.40.16+ds
SRC=ollama-$UPV
mkdir -p "$OUT" "$DL"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
git -C "$TREE" diff --quiet "$PACKAGING_COMMIT" -- sparky-os/packages/ollama || { echo "the recipe differs from $PACKAGING_COMMIT: commit first" >&2; exit 1; }
. "$TREE/sparky-os/repo/build-provenance.sh"
sparky_provenance_init "$IMAGE" "$HERE"
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/ollama.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir "$WORK/orig" "$WORK/recipe"
git -C "$TREE" archive --format=tar "$PACKAGING_COMMIT" sparky-os/packages/ollama | tar -x -C "$WORK/recipe" --strip-components=3

# The orig tarballs are made once from the pinned inputs and kept in DOWNLOADS/orig-$UPV; make-orig.sh gives the same bytes
# for the same inputs, so a later run reuses them (delete the folder to make them again).
CACHE=$DL/orig-$UPV
if [ ! -f "$CACHE/ollama_$UPV.orig.tar.xz" ] || [ ! -f "$CACHE/ollama_$UPV.orig-release.tar.xz" ]; then
	docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}ollama-orig" --pull=never --platform linux/amd64 --cpus "${CPUS:-4}" \
		--ulimit core=1 --network "${ORIG_NETWORK:-none}" --user "$(id -u):$(id -g)" -e HOME=/tmp \
		--mount "type=bind,src=$WORK/recipe,dst=/recipe,readonly" --mount "type=bind,src=$DL,dst=/dl" --mount "type=bind,src=$WORK/orig,dst=/orig" \
		"$IMAGE" bash /recipe/make-orig.sh /dl /orig
	mkdir -p "$CACHE"
	cp "$WORK"/orig/ollama_"$UPV".orig*.tar.xz "$CACHE"/
else
	echo "orig tarballs from $CACHE (made by an earlier run of make-orig.sh):"
	cp "$CACHE"/ollama_"$UPV".orig*.tar.xz "$WORK/orig/"
	(cd "$WORK/orig" && sha256sum ollama_"$UPV".orig*.tar.xz)
fi

tar -xJf "$WORK/orig/ollama_$UPV.orig.tar.xz" -C "$WORK"
tar -xJf "$WORK/orig/ollama_$UPV.orig-release.tar.xz" -C "$WORK/$SRC"
mv "$WORK"/orig/ollama_"$UPV".orig*.tar.xz "$WORK"/
cp -a "$WORK/recipe/debian" "$WORK/$SRC/debian"
echo "packaging: $PACKAGING_COMMIT"
DEBV=$(dpkg-parsechangelog -l "$WORK/$SRC/debian/changelog" -S Version)
[ "${DEBV%-*}" = "$UPV" ] || { echo "debian/changelog is $DEBV, not $UPV" >&2; exit 1; }

docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}ollama-build" --pull=never --platform linux/amd64 --cpus "${CPUS:-4}" \
	--ulimit core=1 --network none --user "$(id -u):$(id -g)" -e HOME=/tmp "${SPARKY_PROV_ARGS[@]}" \
	--mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$TREE/sparky-os,dst=/toolkit,readonly" \
	--mount "type=bind,src=$WORK/recipe,dst=/recipe,readonly" "$IMAGE" bash -c '
set -euo pipefail
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
cd /work
python3 /toolkit/packages/ollama/prepare-lean.py '"$SRC"' "'"$DEBV"'+lc1"
cd '"$SRC"'
if ! dpkg-buildpackage -us -uc -sa > ../build.log 2>&1; then tail -60 ../build.log; exit 1; fi
tail -12 ../build.log
cd ..
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
lintian -I --pedantic ./*.dsc ./*.deb > lintian.txt 2>&1 || true
grep -c "^E:" lintian.txt || true'
mkdir -p "$OUT"
cp -a "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/build.log "$WORK"/lintian.txt "$OUT"/
(cd "$OUT" && sha256sum ./*.deb ./*.dsc ./*.tar.xz > SHA256SUMS)
echo "built: $(cd "$OUT" && ls)"
