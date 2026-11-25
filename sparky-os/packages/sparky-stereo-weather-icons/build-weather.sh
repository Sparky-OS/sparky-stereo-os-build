#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
exec bash "$here/../../repo/build-weather-cohort.sh" "$here" "$@"
