#!/bin/bash
# Build the AAC plugin from verified upstream source with native Lean Code.
# Usage: build.sh [PipeWire upstream version] [matching Debian version]
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PWV=${1:-1.6.9}
DEBV=${2:-1.6.9-2}
OUT=${OUT:-${SPARKY_SCRATCH:?}/bt-aac}
[[ $PWV =~ ^[0-9][0-9.]+$ && $DEBV == "$PWV"-* && $DEBV =~ ^[0-9A-Za-z.+~:-]+$ ]] ||
    { echo "Expected matching upstream and Debian versions" >&2; exit 2; }
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
[ ! -e "$OUT/pipewire-bluez5-codec-aac_${DEBV}+aac2+lc1_amd64.deb" ] ||
    { echo "Use a fresh output directory; this version already exists" >&2; exit 2; }
docker run --rm --cpus "${CPUS:-4}" \
    -v "$OUT:/out" -v "$HERE:/recipe:ro" -v "$HERE/../..:/toolkit:ro" \
    -e PWV="$PWV" -e DEBV="$DEBV" -e HOSTID="$(id -u):$(id -g)" \
    debian:testing bash /recipe/build-in-container.sh
