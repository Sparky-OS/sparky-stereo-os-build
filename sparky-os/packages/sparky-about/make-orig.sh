#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Network preparation only; verified outside inputs stay in the build archive, never in git.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
python3 "$HERE/../../repo/fetch-sparky-display-inputs.py" "$HERE/upstream.json" "${1:?output folder in the build archive}"
