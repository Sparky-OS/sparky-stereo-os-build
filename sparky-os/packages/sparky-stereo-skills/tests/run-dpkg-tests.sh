#!/bin/bash
# Usage: DEBS=dir-with-the-new-debs PUBLISHED=dir-with-the-published-sparky-stereo-skills-deb [IMAGE=...] tests/run-dpkg-tests.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
exec docker run --rm --network none --ulimit core=0 --tmpfs /tmp:mode=1777,exec -e LANG=C.UTF-8 \
	-v "${DEBS:?}:/debs:ro" -v "${PUBLISHED:?}:/published:ro" -v "$HERE:/tests:ro" "${IMAGE:-skills-mcp-430-build:1}" bash /tests/dpkg-tests.sh
