#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Runs tests/detection.py in a debian:testing container with the package's files laid into the
# container's root (payload.sh), without building the .deb or installing its dependencies: the
# fixture mode needs python3 and the tool's own files only. Usage: container-detection.sh [package-dir]
# (default: the package this test belongs to; give an older checkout to see the test fail on it).
# Last update 2026/10/05
set -euo pipefail
PKG=$(cd "${1:-$(dirname "$0")/..}" && pwd)
TESTS=$(cd "$(dirname "$0")" && pwd)
docker run --rm -e DEBIAN_FRONTEND=noninteractive -v "$PKG":/pkg:ro -v "$TESTS":/tests:ro debian:testing bash -c '
apt-get update -qq >/dev/null && apt-get install -y -qq python3 >/dev/null
D=/ HERE=/pkg source /pkg/payload.sh
mkdir -p /pkg-tests-run && cp -r /tests/. /pkg-tests-run/
python3 /pkg-tests-run/detection.py' 2>&1
