#!/bin/bash
# Sparky Stereo OS: runs the kwin DRM and stereo autotests on the source tree of a build.sh run.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Usage: test.sh WORK TESTS   (WORK: the build.sh folder; TESTS: an empty folder for the test build and the logs)
# The render node is passed in for testStereoPair. testMockDrmFrameSequential hangs in some runs of the
# +stereo3d28 source as well; the others must pass (testMockDrmStereoPair 19 of 19).
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(cd "$1" && pwd)
TESTS=$(mkdir -p "$2" && cd "$2" && pwd)
NODE=/dev/dri/renderD128
docker run --rm --cpus 4 --platform linux/amd64 --device "$NODE" --group-add "$(stat -c %g "$NODE")" \
	-v "$TESTS":/t -v "$WORK":/work:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/test-in-container.sh > /t/test.log 2>&1'
cat "$TESTS/test.log"
