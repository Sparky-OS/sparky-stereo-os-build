#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${OUT:?Set OUT to an owned output folder}"
python3 "$HERE/../../repo/build-sparky-display-tool.py" "$HERE" "$OUT" "${SPARKY_DISPLAY_INPUTS:?verified input folder from make-orig.sh}"
