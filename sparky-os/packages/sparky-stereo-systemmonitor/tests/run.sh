#!/bin/bash
# tests/run.sh [PROGRAM DATA]: the catalogues and the presets' tests. Run it in a Debian testing container with
# python3, libkf6config-bin (kreadconfig6, kwriteconfig6), ksystemstats and sparky-stereo-problems; by default on the
# source tree (PROGRAM bin/overview-pages, DATA the package folder, whose lang/ the program reads).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PROGRAM=${1:-$HERE/../bin/overview-pages}
DATA=${2:-$HERE/..}
status=0
python3 -I "$HERE/catalogs.py" || status=1
python3 "$HERE/compose.py" "$PROGRAM" "$DATA" || status=1
exit $status
