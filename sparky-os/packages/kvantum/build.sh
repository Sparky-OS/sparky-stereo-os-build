#!/bin/bash
# Sparky Stereo OS: builds kvantum 1.1.8-1+stereo3d1+lc1 from Debian's 1.1.8-1 source package: Debian's packaging as it is,
# plus the scroll-arrows-together patch (a theme key that puts both scroll arrows at the end of the scrollbar, queue row
# 147), with Lean Code; then the scroll-arrow test on the built packages.
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR
#   WORK          an empty folder; the source closure lands in WORK/lc, the test's results in WORK/test
#   PREVIOUS_DIR  Debian's 1.1.8-1 binary packages, the link gate's predecessors
#   SOURCE_DIR    Debian's kvantum_1.1.8-1.dsc with the files it names, checked against source.sha256
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example (SPARKY_REPO_DIR, a published
# tree with dists/mashtabba; SPARKY_LC_ARCHIVE_DIR, the link gate's folder with sources.json and its keyrings).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR SPARKY_LC_ARCHIVE_DIR
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
(cd "$SRC" && sha256sum -c "$HERE/source.sha256")
IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}
name=${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}kvantum-build-$$
sparky_provenance_init "$IMAGE"
status=0
docker run --rm --ulimit core=1 --name "$name" --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$WORK":/work -v "$SRC":/src:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1' || status=$?
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/build.log" >&2; exit 1; }
# the test: our build must put the arrows together for the theme that asks, and leave the other theme as before
status=0
docker run --rm --ulimit core=1 --name "$name-test" --cpus 4 --platform linux/amd64 \
	-v "$WORK":/work -v "$HERE/tests/scroll-arrows":/test:ro -v "$SPARKY_REPO_DIR":/repo:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"${SPARKY_TEST_IMAGE:-$IMAGE}" bash -c 'trap "chown -R 1000:1000 /work/test" EXIT; sh /run/https-only-apt.sh && cd /work/lc &&
		bash /test/test.sh /work/test together ./qt-style-kvantum_*+lc1_amd64.deb ./qt-style-kvantum-themes_*+lc1_all.deb' || status=$?
[ "$status" = 0 ] || { echo "the scroll-arrow test failed (exit $status): $WORK/test/verdict.txt" >&2; exit 1; }
cat "$WORK/test/verdict.txt"
