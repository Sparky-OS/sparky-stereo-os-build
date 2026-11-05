#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds qt6-multimedia 6.11.2-3+stereo3d14+lc1 or dragon 4:26.04.0-1+stereo3d7+lc1 (depth as a 3D source,
# ORDER 151 step R part 2, group 2, and the offer to save the 3D correction into the file, ORDER 411) from the source next-source.sh made, through Lean Code (build-in-container.sh): the debs
# are built from the +lc1 source with the link and start gate against the earlier +lc1 build, then lean.release check-debs.
# Usage: build.sh PACKAGE WORK SOURCE_DIR PREVIOUS_DIR REPO_DIR ARCHIVE_DIR [NEW_DIR [PREVIOUS_SIBLINGS_FILE]]
#   SOURCE_DIR: the folder next-source.sh wrote (the new .dsc and Debian tarball) with the orig tarball beside them
#   PREVIOUS_DIR: the published +lc1 .deb files of the package, for the link gate
#   REPO_DIR: the signed published tree the build dependencies come from (read only)
#   ARCHIVE_DIR: the link gate's folder, mounted at /archive: sources.json and keyrings/ (sparky-os/lean/archive.md)
#   NEW_DIR: a flat repository (Packages, Release) of debs built earlier in the round (dragon needs qt6-multimedia's)
#   PREVIOUS_SIBLINGS_FILE (also the siblings of the candidate side, as the publisher supplies the destination pool): the published edition's .deb files, one path per line as the container sees them (/repo/pool/...),
#   the previous edition snapshot the link gate resolves edition libraries from (publish-tree.sh makes it from the indexes); without
#   it a library only the edition ships (libavutil61 +stereo3d, which Debian and deb-multimedia version higher) resolves from
#   the public archives and the gate fails
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
PKG=$1
WORK=$(mkdir -p "$2" && cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
PREV=$(cd "$4" && pwd)
REPO=$(cd "$5" && pwd)
ARCHIVE=$(cd "$6" && pwd)
NEW=${7:+$(cd "$7" && pwd)}
SIBS=${8:+$(readlink -f "$8")}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
mkdir -p "$WORK/home"
sparky_provenance_init sparky-lc-migration:20261020
# the candidate side supplies the edition without this package's own earlier binaries and those of ROUND_SOURCES (the sources built earlier in the round) (the gate refuses two versions of one supplied package)
if [ -n "$SIBS" ]; then
	cp "$SIBS" "$WORK/siblings-current.txt"
	for src in $PKG ${ROUND_SOURCES:-}; do grep -v "/pool/main/./$src/" "$WORK/siblings-current.txt" > "$WORK/siblings-current.tmp" || true; mv "$WORK/siblings-current.tmp" "$WORK/siblings-current.txt"; done
fi
# and with the debs built earlier in the round (/new), which the candidate may depend on
[ -z "$SIBS" ] || [ -z "$NEW" ] || for d in "$NEW"/*.deb; do case $d in *-dbgsym_*|*-lc-hr_*) ;; *) echo "/new/$(basename "$d")" >> "$WORK/siblings-current.txt" ;; esac; done
docker run --rm --name "${BUILD_NAME_PREFIX:-d411-build}-$PKG" --cpus "${THREADS:-6}" --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e PKG="$PKG" -e THREADS="${THREADS:-6}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$ARCHIVE":/archive:ro -v "$WORK":/work -v "$SRC":/src:ro -v "$REPO":/repo:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro ${NEW:+-v "$NEW":/new:ro} ${SIBS:+-v "$SIBS":/previous-siblings.txt:ro -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt -v "$WORK/siblings-current.txt":/siblings.txt:ro -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt} \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	--entrypoint bash sparky-lc-migration:20261020 -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1'
