#!/bin/bash
set -euo pipefail
export LC_ALL=C
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
python3 scripts/runner.py status "$PWD"
