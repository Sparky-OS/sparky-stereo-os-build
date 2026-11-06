#!/bin/bash
# Shows the two lint tests going red on a copy of the tree that breaks the rule on purpose, in a container.
# Needs the test binaries from scripts/run-tests.sh in $OUT/out/tests. Prints "RED as expected" or fails.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory used by run-tests.sh}
IMAGE=${IMAGE:-skills-mcp-430-base:1}
W=$(mktemp -d "$OUT/negctl.XXXXXX")
trap 'rm -rf "$W"' EXIT
cp -r "$HERE/compiled" "$HERE/surfaces" "$HERE/tests" "$HERE/data" "$W/"
printf 'const find = @import("find");\n' > "$W/compiled/L4_atomic/manifest/upward.zig"
printf 'pub const era = "stateless_2026_07_28";\n' > "$W/compiled/L5_executable/hardcoded.zig"
docker run --rm --network none --ulimit core=0 --user "$(id -u):$(id -g)" -v "$W:/w:ro" -v "$OUT/out/tests:/t:ro" -w /w "$IMAGE" bash -c '
	for t in lint_layers_test lint_no_hardcoded_variants_test; do
		if /t/$t >/dev/null 2>&1; then echo "NOT RED: $t"; exit 1; else echo "RED as expected: $t"; fi
	done'
