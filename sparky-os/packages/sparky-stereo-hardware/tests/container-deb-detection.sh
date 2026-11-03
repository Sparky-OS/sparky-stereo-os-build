#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Runs this checkout's tests/detection.py and tests/nvidia-branches.py against a built sparky-stereo-hardware .deb (its
# files unpacked into a debian:testing container's root, without its dependencies: the fixture mode needs python3 and the
# tool's own files), so a test can be shown red on a published package and green on a new one (ORDER 354: on 0.1.16 a
# Pascal card gets no driver offer). Usage: container-deb-detection.sh PACKAGE.deb   (IMAGE: an amd64 debian:testing image)
# Last update 2026/11/02
set -uo pipefail
DEB=$(realpath "${1:?a sparky-stereo-hardware .deb}")
TESTS=$(cd "$(dirname "$0")" && pwd)
docker run --rm --platform linux/amd64 -e DEBIAN_FRONTEND=noninteractive -v "$DEB":/in/hardware.deb:ro -v "$TESTS":/tests:ro \
	"${IMAGE:?an amd64 debian:testing image}" bash -c '
apt-get update -qq >/dev/null && apt-get install -y -qq python3 >/dev/null
dpkg-deb -x /in/hardware.deb / && dpkg-deb -f /in/hardware.deb Package Version
mkdir -p /pkg-tests-run && cp -r /tests/. /pkg-tests-run/
status=0
python3 /pkg-tests-run/detection.py || status=1
python3 /pkg-tests-run/nvidia-branches.py || status=1
exit $status' 2>&1
