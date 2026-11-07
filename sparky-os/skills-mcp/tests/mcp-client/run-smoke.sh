#!/bin/bash
# Drives the built program with the official MCP SDK client in the mcpclient image (built with the network, run without).
# Usage: OUT=/scratch tests/mcp-client/run-smoke.sh      (needs $OUT/out/bin/sparky-stereo-skills from `zig build`)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory}
exec docker run --rm --network none --ulimit core=0 --user "$(id -u):$(id -g)" --tmpfs /tmp:mode=1777,exec \
	-v "$HERE:/product:ro" -v "$OUT/out/bin/sparky-stereo-skills:/usr/bin/sparky-stereo-skills:ro" -e HOME=/tmp/home \
	"${IMAGE:-skills-mcp-430-mcpclient:1}" bash /product/tests/mcp-client/smoke-inside.sh
