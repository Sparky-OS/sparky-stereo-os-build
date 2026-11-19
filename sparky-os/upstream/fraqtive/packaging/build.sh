#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 743: builds fraqtive 0.4.8.1-1+stereo3d1+lc1 (Debian's source plus the two patches of ../patches)
# by the edition's route: next-source.sh makes the +lc1 source, then packages/depth-source/build.sh builds it through Lean Code
# with the link and start gate, the HR companion and the build record (lean.release check-debs).
# Usage: build.sh WORK PUBLISHED_TREE ARCHIVE_DIR
#   WORK: a new empty folder; PUBLISHED_TREE: the signed published tree (its real path, read only); ARCHIVE_DIR: the link gate's
#   folder (sources.json and keyrings/, sparky-os/lean/archive.md). Environment: SPARKY_BUILD_IMAGE (the Lean Code migration
#   image, default sparky-lc-migration:20261020), BUILD_NAME_PREFIX (container names), THREADS (default 4).
# NEW_DIR (environment): a flat repository of debs built earlier in the round (libstereo-declare 1.11 for +stereo3d3).
# Needs a committed recipe: the source is dated by the last commit touching sparky-os/upstream/fraqtive (ORDER 421b).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../repo/build-provenance.sh"
RECIPE=$(cd "$HERE/.." && pwd)
TOOLKIT=$(cd "$RECIPE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^# Usage/,/^# Needs/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
W=$(mkdir -p "$1" && cd "$1" && pwd) TREE=$(readlink -f "$2") ARCHIVE=$(cd "$3" && pwd)
[ -z "$(ls -A "$W")" ] || { echo "$W is not empty" >&2; exit 1; }
IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}
export BUILD_NAME_PREFIX=${BUILD_NAME_PREFIX:-fq743-build} THREADS=${THREADS:-4}
# the host facts of the build record, and the source date (the last commit touching this recipe, ORDER 421b)
SPARKY_SOURCE_DATE_BASIS="the last commit touching sparky-os/upstream/fraqtive"
sparky_provenance_init "$IMAGE" "$RECIPE"
export SPARKY_BUILD_IMAGE=$IMAGE
mkdir -p "$W/src" "$W/prev"
docker run --rm --name "$BUILD_NAME_PREFIX-source" --pull=never --ulimit core=0 --cpus "$THREADS" --platform linux/amd64 \
	"${SPARKY_PROV_ARGS[@]}" \
	--mount type=bind,src="$TOOLKIT",dst=/toolkit,readonly --mount type=bind,src="$RECIPE",dst=/recipe,readonly --mount type=bind,src="$W/src",dst=/out \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly --mount type=bind,src="$TOOLKIT/../tools/https-only-apt.sh",dst=/run/https-only-apt.sh,readonly \
	--entrypoint bash "$IMAGE" -c 'sh /run/https-only-apt.sh && bash /recipe/packaging/next-source.sh /out' >"$W/next-source.log" 2>&1 \
	|| { tail -30 "$W/next-source.log"; exit 1; }
# the published edition's .deb files as the build container sees them: what the publisher supplies as the destination pool
(cd "$TREE" && find pool -name '*.deb' ! -name '*-lc-hr_*' ! -name '*-dbgsym_*' | LC_ALL=C sort | sed 's|^|/repo/|') > "$W/siblings.txt"
ROUND_SOURCES=${NEW_DIR:+stereo-declare} "$TOOLKIT/packages/depth-source/build.sh" fraqtive "$W/work" "$W/src" "$W/prev" "$TREE" "$ARCHIVE" "${NEW_DIR:-}" "$W/siblings.txt" \
	|| { echo "the build failed; the end of its log:" >&2; tail -40 "$W/work/build.log" >&2; exit 1; }
grep -E 'link check passed|verified [0-9]+ packages' "$W/work/build.log" | tail -4
