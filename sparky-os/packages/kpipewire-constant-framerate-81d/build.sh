#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, queue row 81 part D: makes kpipewire 6.7.4-1+stereo3d10 with next-source.sh and builds its packages through
# Lean Code (the link and start gate of debian/sparky-lean, then lean.release check-debs, which writes the build record), in one
# container of the Lean Code migration image, after ../kpipewire-740/build.sh.
# Usage: build.sh BASE_DIR WORK PUBLISHED_TREE ARCHIVE_DIR PREVIOUS_DIR
#   BASE_DIR: ORDER 740's kpipewire_6.7.4-1+stereo3d9 source (.dsc, Debian tarball, orig tarball), read only
#   WORK: an empty folder; it receives src/ (the new .dsc, Debian tarball, orig tarball, both changelogs, the successor report)
#     and lc/ (the packages, buildinfo, changes and the build record), build.log and build-dep.log
#   PUBLISHED_TREE: the signed published tree the build dependencies come from (read only)
#   ARCHIVE_DIR: the link gate's folder (sources.json and its keyrings, sparky-os/lean/archive.md), read only
#   PREVIOUS_DIR: the packages this build follows (ORDER 740's +stereo3d9), for the link gate
# Environment: SPARKY_BUILD_IMAGE (default sparky-lc-migration:20261020; a lane names its own tag of it), BUILD_NAME_PREFIX
# (container name, default kpw81d-build), THREADS (default 4).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
BASE=$(cd "$1" && pwd)
WORK=$(mkdir -p "$2" && cd "$2" && pwd)
TREE=$(cd "$3" && pwd)
ARCHIVE=$(cd "$4" && pwd)
PREV=$(cd "$5" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --pull=never --name "${BUILD_NAME_PREFIX:-kpw81d-build}-kpipewire" --ulimit core=1 --cpus "${THREADS:-4}" --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e THREADS="${THREADS:-4}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	--mount type=bind,src="$BASE",dst=/base,readonly --mount type=bind,src="$WORK",dst=/work --mount type=bind,src="$TREE",dst=/repo,readonly \
	--mount type=bind,src="$ARCHIVE",dst=/archive,readonly --mount type=bind,src="$PREV",dst=/prev,readonly \
	--mount type=bind,src="$HERE/../..",dst=/toolkit,readonly \
	--mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
	--mount type=bind,src="$HERE/../../../tools/https-only-apt.sh",dst=/run/https-only-apt.sh,readonly \
	--entrypoint bash "$IMAGE" -c 'sh /run/https-only-apt.sh && bash /toolkit/packages/kpipewire-constant-framerate-81d/build-in-container.sh > /work/build.log 2>&1'
grep -E 'link check passed|verified [0-9]+ packages' "$WORK/build.log" | tail -4
ls "$WORK/src" "$WORK/lc"
