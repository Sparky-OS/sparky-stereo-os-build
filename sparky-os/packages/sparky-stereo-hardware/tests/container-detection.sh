#!/bin/bash
# Runs tests/detection.py in a debian:testing container with the package's files laid into the
# container's root (payload.sh), without building the .deb or installing its dependencies: the
# fixture mode needs python3 and the tool's own files only. payload.sh calls sparky-stereo-problems
# (it builds the journal catalogs), so the container installs that package from the published tree.
# Usage: SPARKY_TREE=/path/to/published/tree container-detection.sh [package-dir]
#   SPARKY_TREE  a published apt tree (dists/mashtabba and pool), read only: the source of sparky-stereo-problems
#   IMAGE        the container image (default debian:testing; pin it by digest on a shared machine)
#   package-dir  default: the package this test belongs to; give an older checkout to see the test fail on it.
# Last update 2026/11/16
set -euo pipefail
PKG=$(cd "${1:-$(dirname "$0")/..}" && pwd)
TESTS=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "${SPARKY_TREE:?set SPARKY_TREE to a published apt tree (the source of sparky-stereo-problems)}" && pwd)
docker run --rm --ulimit core=0 -e DEBIAN_FRONTEND=noninteractive -v "$PKG":/pkg:ro -v "$TESTS":/tests:ro -v "$TREE":/tree:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$(dirname "$(readlink -f "$0")")/../../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "${IMAGE:-debian:testing}" bash -c '
sh /run/https-only-apt.sh
apt-get update -qq >/dev/null && apt-get install -y -qq python3 >/dev/null
printf "deb [trusted=yes] file:/tree mashtabba main\n" >/etc/apt/sources.list.d/tree.list
apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends sparky-stereo-problems >/dev/null
D=/ HERE=/pkg source /pkg/payload.sh
mkdir -p /pkg-tests-run && cp -r /tests/. /pkg-tests-run/
python3 /pkg-tests-run/detection.py
python3 /pkg-tests-run/nvidia-branches.py' 2>&1
