#!/bin/bash
# Sparky Stereo OS: checks one build's qt6-base development headers in a fresh debian:testing container (check-headers.py):
# each public module header compiles, alone and all together, and every #include in every installed header resolves.
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Usage: test.sh DEB_DIR RESULTS   (DEB_DIR: a folder holding one build's qt6-base .deb files, such as build.sh's WORK/lc or
#   the repository's pool/main/q/qt6-base; the word debian tests Debian's own qt6-base from Debian testing instead, the
#   control; RESULTS: an empty folder for test.log, summary.txt and a log per failing case). The build's packages are
#   installed first, their dependencies from the edition's tree (SPARKY_REPO_DIR) and Debian testing.
# +stereo3d13 fails it: its QtCore module header includes five headers no package ships (ORDER 308).
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
IMAGE=debian@sha256:fe4be93b807e7d05dccdaf54931173d9368b349f91a8170dadd787213aa3bf19
RESULTS=$(mkdir -p "$2" && cd "$2" && pwd)
[ -z "$(ls -A "$RESULTS")" ] || { echo "$RESULTS is not empty" >&2; exit 1; }
MOUNTS=()
if [ "$1" != debian ]; then
	sparky_need SPARKY_REPO_DIR
	MOUNTS=(-v "$(cd "$1" && pwd)":/debs:ro -v "$SPARKY_REPO_DIR":/repo:ro)
fi
status=0
docker run --rm --cpus 4 --platform linux/amd64 "${MOUNTS[@]}" -v "$RESULTS":/t -v "$HERE":/tools:ro \
	"$IMAGE" bash -c 'bash /tools/test-in-container.sh > /t/test.log 2>&1' || status=$?
cat "$RESULTS/summary.txt" 2>/dev/null || tail -20 "$RESULTS/test.log"
exit $status
