#!/bin/bash
set -euo pipefail
export LC_ALL=C
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
touch pause.request
echo 'Pause requested after the current whole step. ./run.sh resumes.'
