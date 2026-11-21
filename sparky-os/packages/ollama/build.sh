#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Ollama 0.40.16+ds from upstream's release build, split by hardware (ollama, ollama-cuda, ollama-rocm).
# make-orig.sh makes the two upstream tarballs from the inputs release.tsv pins (the only step that may read the network, and only
# for an input DOWNLOADS lacks); the package is then built in a container, its payload qualified by Lean Code without compilation
# (prepare-lean.py) and checked by Lean Code's link and start gate, lean.release check-debs and lintian. The gate's APT reads the
# public archives SPARKY_LC_ARCHIVE_DIR/sources.json names (Debian, and NVIDIA's repository for ollama-cuda's dependencies), so
# that step has the network, as release/build-dh-lean.sh's has; the gate runs the packages' programs in bubblewrap with no network.
# SPARKY_LC_ARCHIVE_DIR (required): the gate's folder, mounted at /archive (sparky-os/lean/archive.md).
# SPARKY_LC_SIBLINGS_FILE (optional): the edition .deb files the gate may resolve against, one path per line (ollama depends on
#   sparky-stereo-graphics, whose closure is the edition's own Qt and KDE packages); their folders are mounted read only.
# Usage: build.sh OUT DOWNLOADS [PACKAGING_COMMIT]   (OUT an empty folder; DOWNLOADS keeps the pinned inputs)
# IMAGE: a Debian testing image with dpkg-dev, debhelper, lintian, python3, python3-yaml, node-acorn, zstd, xz-utils, git and curl.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
DL=$(realpath -m "${2:?downloads folder}")
PACKAGING_COMMIT=$(git -C "$TREE" rev-parse --verify "${3:-HEAD}^{commit}")
IMAGE=${IMAGE:?a build image}
ARCHIVE=$(realpath "${SPARKY_LC_ARCHIVE_DIR:?the link gate folder: sources.json and its keyrings (sparky-os/lean/archive.md)}")
[ -f "$ARCHIVE/sources.json" ] || { echo "no $ARCHIVE/sources.json" >&2; exit 2; }
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

mkdir -p "$WORK/link-scratch"
SIBLING_ARGS=()
if [ -n "${SPARKY_LC_SIBLINGS_FILE:-}" ]; then
	SIBLING_ARGS=(-v "$(realpath "$SPARKY_LC_SIBLINGS_FILE")":/siblings.list:ro -e SPARKY_LC_SIBLINGS_FILE=/siblings.list)
	while read -r dir; do SIBLING_ARGS+=(-v "$dir":"$dir":ro); done < <(xargs -d '\n' -n1 dirname < "$SPARKY_LC_SIBLINGS_FILE" | sort -u)
fi
# the gate isolates each case with bubblewrap, which needs the container's /proc unmasked (as release/build-dh-lean.sh)
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}ollama-build" --pull=never --platform linux/amd64 --cpus "${CPUS:-4}" \
	--ulimit core=1 --user "$(id -u):$(id -g)" -e HOME=/tmp "${SPARKY_PROV_ARGS[@]}" "${SIBLING_ARGS[@]}" \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
	--mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$TREE/sparky-os,dst=/toolkit,readonly" \
	--mount "type=bind,src=$WORK/recipe,dst=/recipe,readonly" "$IMAGE" bash -c '
set -euo pipefail
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
cd /work
python3 /toolkit/packages/ollama/prepare-lean.py '"$SRC"' "'"$DEBV"'+lc1"
# debian/ (the recipe and the Lean toolkit prepare-lean.py copies in) gets the recipe'"'"'s date and modes: dpkg-source only clamps
# newer times, so a toolkit checked out before that date kept its checkout time in the debian tarball (ORDER 70, +ds-2)
python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" '"$SRC"'
cd '"$SRC"'
if ! dpkg-buildpackage -us -uc -sa > ../build.log 2>&1; then tail -60 ../build.log; exit 1; fi
tail -12 ../build.log
cd ..
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
lintian -I --pedantic ./*.dsc ./*.deb > lintian.txt 2>&1 || true
grep -c "^E:" lintian.txt || true'
mkdir -p "$OUT"
# the stage is the source closure: the archives, the .dsc and every file it names, the buildinfo, the changes and the build record
# lean.release check-debs wrote beside them (it was left in the work folder before, ORDER 70), with the logs
cp -a "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/*.sparky-build.json \
	"$WORK"/build.log "$WORK"/lintian.txt "$OUT"/
# every file of the stage but this list itself
(cd "$OUT" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs sha256sum > SHA256SUMS)
echo "built: $(cd "$OUT" && ls)"
