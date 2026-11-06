#!/bin/bash
# The 157 symptoms through the engine against the rankings recorded in data/golden, in the build image (it has python3).
# Usage: OUT=/scratch PUB=/path/to/public/checkout tests/routing/run-routing.sh      (the checkout at the commit in data/golden/SOURCE)
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory}
PUB=${PUB:?Set PUB to the public checkout}
exec docker run --rm --network none --ulimit core=0 --user "$(id -u):$(id -g)" --tmpfs /tmp:mode=1777,exec \
	-v "$HERE:/product:ro" -v "$PUB:/pub:ro" -v "$OUT/out/bin/sparky-stereo-skills:/usr/bin/sparky-stereo-skills:ro" -e HOME=/tmp/h \
	"${IMAGE:-skills-mcp-430-build:1}" python3 -I /product/tests/routing/compare.py /usr/bin/sparky-stereo-skills /pub /product/data/routing/symptoms-157.tsv /product/data/golden/routing-157-top3.tsv
