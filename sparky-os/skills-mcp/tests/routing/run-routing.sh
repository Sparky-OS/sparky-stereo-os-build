#!/bin/bash
# The 157 symptoms through both engines, in the build image (it has python3): the Zig program and the Python tool it replaces.
# Usage: OUT=/scratch PUB=/path/to/public/checkout tests/routing/run-routing.sh
# ORACLE is the Python tool inside the checkout (tools/skills-context.py, or old_attempts/skills-context.py once moved aside).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory}
PUB=${PUB:?Set PUB to the public checkout}
ORACLE=${ORACLE:-}
if [ -z "$ORACLE" ]; then
	for c in old_attempts/skills-context.py tools/skills-context.py; do [ -f "$PUB/$c" ] && { ORACLE=$c; break; }; done
fi
exec docker run --rm --network none --ulimit core=0 --user "$(id -u):$(id -g)" --tmpfs /tmp:mode=1777,exec \
	-v "$HERE:/product:ro" -v "$PUB:/pub:ro" -v "$OUT/out/bin/sparky-stereo-skills:/usr/bin/sparky-stereo-skills:ro" -e HOME=/tmp/h \
	"${IMAGE:-skills-mcp-430-build:1}" python3 -I /product/tests/routing/compare.py /usr/bin/sparky-stereo-skills /pub "/pub/${ORACLE:?no Python tool found in the checkout}" /product/data/routing/symptoms-157.tsv
