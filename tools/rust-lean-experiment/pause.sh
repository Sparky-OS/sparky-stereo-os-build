#!/bin/bash
set -euo pipefail
export LC_ALL=C
command -v readlink >/dev/null || { echo "Required host tool missing: readlink" >&2; exit 1; }
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
touch pause.request
echo 'Pause requested after the current whole step. ./run.sh resumes.'
