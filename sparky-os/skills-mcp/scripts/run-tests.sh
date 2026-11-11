#!/bin/bash
# Builds every test binary (static musl) with the station's cgm-zig, then runs each one inside a container:
# no network, no core dumps, an ordinary user, the product and the skills checkout read only.
# Usage: OUT=/scratch/dir [SKILLS_SRC=/path/to/skills/checkout] [IMAGE=name:tag] scripts/run-tests.sh [test-name-filter]
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:?Set OUT to a scratch directory}
IMAGE=${IMAGE:-skills-mcp-430-base:1}
SKILLS_SRC=${SKILLS_SRC:-/nonexistent}
FILTER=${1:-}
export ZIG_GLOBAL_CACHE_DIR=$OUT/zig-global ZIG_LOCAL_CACHE_DIR=$OUT/zig-cache
mkdir -p "$OUT"
rm -rf "$OUT/out/tests"
(cd "$HERE" && zig build test-bins --prefix "$OUT/out" -Dskills-src="$SKILLS_SRC")
mounts=(-v "$HERE:/product:ro" -v "$OUT/out/tests:/t:ro")
[ -d "$SKILLS_SRC" ] && mounts+=(-v "$SKILLS_SRC:$SKILLS_SRC:ro")
docker run --rm --network none --ulimit core=0 --tmpfs /tmp:mode=1777 --user "$(id -u):$(id -g)" "${mounts[@]}" -w /product \
	-e FILTER="$FILTER" "$IMAGE" bash -c '
	pass=0; fail=0; failed=()
	for t in /t/*; do
		n=$(basename "$t")
		case "$n" in *"$FILTER"*) ;; *) continue ;; esac
		if out=$("$t" 2>&1); then pass=$((pass+1)); echo "PASS $n"
		else fail=$((fail+1)); failed+=("$n"); echo "FAIL $n"; printf "%s\n" "$out" | sed "s/^/    /" | head -${LINES_PER_FAIL:-12}; fi
	done
	echo "files passing: $pass, files failing: $fail"
	[ "$fail" -eq 0 ]'
