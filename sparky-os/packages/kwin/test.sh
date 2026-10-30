#!/bin/bash
# Sparky Stereo OS: runs the kwin DRM and stereo autotests, the stereo downscale, X11 window and DMA-BUF format tests on the source tree of a build.sh run.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Usage: test.sh WORK TESTS EXTRA_DIR   (WORK: the build.sh folder; TESTS: an empty folder for the test build and the logs;
#   EXTRA_DIR: the build.sh EXTRA_DIR, the plasma-wayland-protocols build the source needs)
# The render node is passed in for testStereoPair, /dev/udmabuf for testDmabufFormatSwitch (it skips without it).
# Up to +stereo3d38, testMockDrmFrameSequential hung in some runs (about 1 run in 10 to 20: a lost wake-up in DrmCommitThread at
# shutdown, fixed in +stereo3d39, which testDrmCommitThread covers); every test must pass (testMockDrmStereoPair 19 of 19).
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(cd "$1" && pwd)
TESTS=$(mkdir -p "$2" && cd "$2" && pwd)
EXTRA=$(cd "$3" && pwd)
NODE=/dev/dri/renderD128
UDMABUF=()
[ -c /dev/udmabuf ] && UDMABUF=(--device /dev/udmabuf --group-add "$(stat -c %g /dev/udmabuf)")
docker run --rm --cpus 4 --platform linux/amd64 --device "$NODE" --group-add "$(stat -c %g "$NODE")" "${UDMABUF[@]}" \
	-v "$TESTS":/t -v "$WORK":/work:ro -v "$EXTRA":/extra:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/test-in-container.sh > /t/test.log 2>&1'
cat "$TESTS/test.log"
