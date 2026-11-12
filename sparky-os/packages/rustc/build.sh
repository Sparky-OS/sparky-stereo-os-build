#!/bin/bash
# Sparky Stereo OS: builds the edition's rustc (every binary package of Debian's rustc source, the runtime package
# libstd-rust-HASH and their Lean Code HR companions) from Debian's rustc source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/12
# Copyright 2026 under the GNU GPL3 License
# Usage: build.sh VERSIONS_FILE WORK SOURCE_DIR [SEED_DIR]
#   VERSIONS_FILE: versions/1.98.1.env or versions/1.99.1.env; WORK: a new or empty folder on a disk with 60 GB free;
#   SOURCE_DIR: the folder holding Debian's rustc .dsc, .debian.tar.xz and .orig.tar.xz, as apt-get source downloads them;
#   SEED_DIR: the folder with the edition's previous compiler packages (out/ of the previous link); without it the seed
#   is Debian testing's rustc, as Debian's README.source prescribes. No compiler binary is downloaded: the compile runs
#   in a container without network.
# The candidates and their SHA256SUMS land in WORK/out, the logs in WORK. Set SPARKY_DISK_FLOOR_GIB (default 12) and
# SPARKY_DISK_PATH (default WORK) for the disk guard: the build is killed 1 GiB above the floor.
# Run Lean Code's link and start gate (python3 -m lean.release check-link) on WORK/out's archives afterwards.
# Last update 2026/11/12
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
VERSIONS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
WORK=$(mkdir -p "$2" && cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
SEED=${4:+$(cd "$4" && pwd)}
: "${BASE_IMAGE:?a Debian testing amd64 image, pinned by digest}" "${SPARKY_CONTAINER_PREFIX:=rustc-build}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
. "$VERSIONS"
floor=$(( (${SPARKY_DISK_FLOOR_GIB:-12} + 1) * 1024 * 1024 * 1024 ))
disk=${SPARKY_DISK_PATH:-$WORK}
image=$SPARKY_CONTAINER_PREFIX-deps-$UPSTREAM:1
common=(--ulimit core=0 --cpus 4 --memory 24g --platform linux/amd64 -e "VERSION_FILE=/tools/versions/$(basename "$VERSIONS")"
	--mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$SRC,dst=/src,readonly"
	--mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" --mount "type=bind,src=$HERE,dst=/tools,readonly")
[ -z "$SEED" ] || common+=(--mount "type=bind,src=$SEED,dst=/seed,readonly")

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

sparky_provenance_init "$BASE_IMAGE"
date -u +%s >"$WORK/started"
name=$SPARKY_CONTAINER_PREFIX-deps-$UPSTREAM
docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" "${common[@]}" -e STEP=deps \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
	--mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	"$BASE_IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/deps.log 2>&1' >/dev/null
while [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ]; do sleep 5; done
[ "$(docker wait "$name")" = 0 ] || { docker rm "$name" >/dev/null; echo "the deps step failed: $WORK/deps.log" >&2; exit 1; }
docker commit "$name" "$image" >/dev/null
docker rm "$name" >/dev/null
date -u +%s >"$WORK/deps-done"

sparky_provenance_init "$image"
name=$SPARKY_CONTAINER_PREFIX-build-$UPSTREAM
docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" --network none "${common[@]}" -e STEP=build \
	"$image" bash -c 'bash /tools/build-in-container.sh > /work/container.log 2>&1' >/dev/null
if ! guarded "$name"; then
	[ ! -e "$WORK/disk-guard.stop" ] || exit 1
	if [ "$STD_HASH" = discover ] && [ -s "$WORK/STD_HASH.found" ]; then
		found=$(cat "$WORK/STD_HASH.found")
		echo "first build of rustc $UPSTREAM: its standard library is libstd-$found.so. Record STD_HASH=$found in $VERSIONS; packaging the compiled tree with that name now."
		name=$SPARKY_CONTAINER_PREFIX-repackage-$UPSTREAM
		docker run "${SPARKY_PROV_ARGS[@]}" -d --name "$name" --network none "${common[@]}" -e STEP=repackage -e "STD_HASH_FOUND=$found" \
			"$image" bash -c 'bash /tools/build-in-container.sh > /work/container-2.log 2>&1' >/dev/null
		guarded "$name" || { echo "the repackage step failed: $WORK/container-2.log, $WORK/build-2.log" >&2; exit 1; }
		final=$WORK/source-final
	else
		echo "the build failed: $WORK/container.log, $WORK/build.log" >&2
		exit 1
	fi
else
	final=$WORK/source
fi
date -u +%s >"$WORK/build-done"
mkdir -p "$WORK/out/source"
cp "$WORK"/*.deb "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK/out/"
cp "$final"/lc/*+lc1.dsc "$final"/lc/*+lc1.debian.tar.xz "$final"/lc/*.orig.tar.xz "$WORK/out/source/"
(cd "$WORK/out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS)
echo "done: $WORK/out ($(ls "$WORK/out"/*.deb | wc -l) archives)"
