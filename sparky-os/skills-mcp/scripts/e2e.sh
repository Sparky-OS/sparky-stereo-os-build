#!/bin/bash
# End to end: the installed-style program driven through its three faces (command line, MCP in both eras, registration)
# inside a container (no network, no core dumps, ordinary user). Needs $OUT/out/bin/sparky-stereo-skills from `zig build`.
# Usage: OUT=/scratch scripts/e2e.sh        (set AS_ROOT=1 to run only the root refusal check)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory}
IMAGE=${IMAGE:-skills-mcp-430-base:1}
user=$(id -u):$(id -g)
[ "${AS_ROOT:-}" = 1 ] && user=0:0
exec docker run --rm --network none --ulimit core=0 --user "$user" --tmpfs /tmp:mode=1777,exec \
	-v "$HERE:/product:ro" -v "$OUT/out/bin/sparky-stereo-skills:/usr/bin/sparky-stereo-skills:ro" -e AS_ROOT="${AS_ROOT:-}" \
	-w /product "$IMAGE" bash /product/scripts/e2e-inside.sh
