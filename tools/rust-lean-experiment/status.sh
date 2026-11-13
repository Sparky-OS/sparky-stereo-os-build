#!/bin/bash
set -euo pipefail
export LC_ALL=C
command -v readlink >/dev/null || { echo "Required host tool missing: readlink" >&2; exit 1; }
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
python3 scripts/runner.py status "$PWD"
