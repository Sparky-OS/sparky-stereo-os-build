#!/bin/bash
# Sparky Stereo OS: builds the Craft suite's packages (one per app, the shared library, craft-suite-common and their
# Lean Code HR companions) from the folder fetch.sh made, with the edition's own rustc and no network.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Usage: build.sh WORK SOURCES SEED_DIR [STEP]
#   WORK: a new or empty folder on a disk with 30 GB free; SOURCES: the folder fetch.sh wrote; SEED_DIR: the folder
#   with the edition's rustc, cargo and libstd-rust packages (out/ of the rustc recipe). STEP: all (default); deps
#   (stop once the image with the compiler, the build dependencies and the two source packages exists); build (go on
#   from there); source (the two source packages only, again, in WORK/source: the reproducible-source check).
# The compile runs in a container without network: a crate, a font or a catalogue that is not in SOURCES stops it.
# The candidates and their SHA256SUMS land in WORK/out, the logs in WORK. SPARKY_DISK_FLOOR_GIB (default 12) and
# SPARKY_DISK_PATH (default WORK) set the disk guard: the build is killed 1 GiB above the floor.
# Run Lean Code's link and start gate (python3 -m lean.release check-link) on WORK/out's archives afterwards.
# Last update 2026/11/13
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
SEED=$(cd "$3" && pwd)
STEP=${4:-all}
: "${BASE_IMAGE:?a Debian testing amd64 image, pinned by digest}" "${SPARKY_CONTAINER_PREFIX:=craft-suite}"
floor=$(( (${SPARKY_DISK_FLOOR_GIB:-12} + 1) * 1024 * 1024 * 1024 ))
disk=${SPARKY_DISK_PATH:-$WORK}
image=$SPARKY_CONTAINER_PREFIX-deps:1
# SUITE_RUSTC, SUITE_STD_PACKAGE and SUITE_EDITION replace suite.json's compiler, its runtime package and the edition
# suffix for one run: an earlier release for an update rehearsal is built that way (another compiler, a lower suffix).
common=(--ulimit core=0 --cpus 4 --memory 24g --platform linux/amd64 -e "SUITE_RUSTC=${SUITE_RUSTC:-}" -e "SUITE_STD_PACKAGE=${SUITE_STD_PACKAGE:-}" -e "SUITE_EDITION=${SUITE_EDITION:-}"
	--mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$SRC,dst=/src,readonly" --mount "type=bind,src=$SEED,dst=/seed,readonly"
	--mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" --mount "type=bind,src=$HERE,dst=/tools,readonly")

guarded() {    # guarded NAME: wait for the container, sampling the disk every 5 s; kill it 1 GiB above the floor
	local name=$1 free low
	low=$(df --output=avail -B1 "$disk" | tail -1)
	while [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" = true ]; do
		free=$(df --output=avail -B1 "$disk" | tail -1)
		[ "$free" -ge "$low" ] || low=$free
		echo "$low" >"$WORK/disk-lowest-free-bytes.$name"
		if [ "$free" -lt "$floor" ]; then
			docker kill "$name" >/dev/null
			echo "disk guard: $disk has $free bytes free, under the floor plus 1 GiB ($floor): $name killed" | tee "$WORK/disk-guard.stop" >&2
		fi
		sleep 5
	done
	status=$(docker wait "$name")
	docker rm "$name" >/dev/null
	[ "$status" = 0 ]
}

if [ "$STEP" = source ]; then
	sparky_provenance_init "$image"
	name=$SPARKY_CONTAINER_PREFIX-source
	docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" --network none "${common[@]}" -e STEP=source \
		"$image" bash -c 'bash /tools/build-in-container.sh > /work/source.log 2>&1' >/dev/null
	guarded "$name" || { echo "the source step failed: $WORK/source.log" >&2; exit 1; }
	cat "$WORK/source/SOURCE-SHA256SUMS"
	exit 0
fi
if [ "$STEP" != build ]; then
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init "$BASE_IMAGE"
date -u +%s >"$WORK/started"
name=$SPARKY_CONTAINER_PREFIX-deps
docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" "${common[@]}" -e STEP=deps \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
	--mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	"$BASE_IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/deps.log 2>&1' >/dev/null
while [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ]; do sleep 5; done
[ "$(docker wait "$name")" = 0 ] || { docker rm "$name" >/dev/null; echo "the deps step failed: $WORK/deps.log" >&2; exit 1; }
docker commit "$name" "$image" >/dev/null
docker rm "$name" >/dev/null
date -u +%s >"$WORK/deps-done"
[ "$STEP" != deps ] || { echo "deps done: image $image, sources in $WORK/source"; exit 0; }
fi

sparky_provenance_init "$image"
name=$SPARKY_CONTAINER_PREFIX-build
docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" --network none "${common[@]}" -e STEP=build \
	"$image" bash -c 'bash /tools/build-in-container.sh > /work/container.log 2>&1' >/dev/null
guarded "$name" || { echo "the build failed: $WORK/container.log, $WORK/build.log" >&2; exit 1; }
date -u +%s >"$WORK/build-done"
# the release gate (lean.release check-debs) writes the build record beside the archives, from the provenance facts
name=$SPARKY_CONTAINER_PREFIX-check
docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" --network none "${common[@]}" -e STEP=check \
	"$image" bash -c 'bash /tools/build-in-container.sh > /work/check-debs.log 2>&1' >/dev/null
guarded "$name" || { echo "check-debs failed: $WORK/check-debs.log" >&2; exit 1; }
mkdir -p "$WORK/out/source"
cp "$WORK"/*.deb "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/*.sparky-build.json "$WORK/out/"
cp "$WORK"/source/lc/*+lc1.dsc "$WORK"/source/lc/*+lc1.debian.tar.xz "$WORK"/source/lc/*.orig.tar.xz "$WORK/out/source/"
(cd "$WORK/out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)
echo "done: $WORK/out ($(ls "$WORK/out"/*.deb | wc -l) archives)"
