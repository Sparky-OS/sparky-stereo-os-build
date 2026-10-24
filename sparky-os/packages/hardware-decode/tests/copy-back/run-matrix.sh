#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# The mpv copy-back matrix, one fresh headless Weston per case, inside a
# container that holds the mpv under test. With the render node of a GPU
# that imports decoded surfaces (zero-copy present), the cases run as they
# are, and with --a10 the test layer makes the same GPU copy-only, as RADV
# is on the A10's Carrizo. NOGPU=1 runs the cases for a container without
# a GPU (none).
# Usage: run-matrix.sh OUTDIR FIXTUREDIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$1 fixtures=$2 work=$3
mkdir -p "$out" "$work/layer"
[ -f "$fixtures/fixtures.sha256" ] || "$here/make-fixtures.sh" "$fixtures"
(cd "$fixtures" && sha256sum -c --quiet fixtures.sha256)
dpkg-query -W -f="\${Package} \${Version}\n" mpv libplacebo360 libmedia-gpu-route0 mesa-vulkan-drivers mesa-va-drivers > "$out/versions.txt" || true
case=("$here/mpv-case.py" --out "$out" --layer-dir "$work/layer")
if [ "${NOGPU:-0}" = 1 ]; then
    "${case[@]}" --name none-2d --film "$fixtures/2d.mkv"
    "${case[@]}" --name none-sbs --film "$fixtures/sbs.mkv"
    exit 0
fi
gcc -shared -fPIC -fvisibility=hidden -O2 -Wall -Wextra -Werror -o "$work/layer/libhide-modifiers-layer.so" "$here/hide-modifiers-layer.c"
cp "$here/hide-modifiers-layer.json" "$work/layer/"
"${case[@]}" --name zc-2d --film "$fixtures/2d.mkv"
"${case[@]}" --name zc-sbs --film "$fixtures/sbs.mkv" --screenshot-at 2
"${case[@]}" --name zc-sbs2 --film "$fixtures/sbs2.mkv" --screenshot-at 2
"${case[@]}" --name zc-tb --film "$fixtures/tb.mkv" --screenshot-at 2
"${case[@]}" --name zc-tb-vaapi --film "$fixtures/tb.mkv" -- --hwdec=vaapi
"${case[@]}" --name sw-sbs --film "$fixtures/sbs.mkv" --screenshot-at 2 -- --hwdec=no
"${case[@]}" --name sw-sbs2 --film "$fixtures/sbs2.mkv" --screenshot-at 2 -- --hwdec=no
"${case[@]}" --name sw-tb --film "$fixtures/tb.mkv" --screenshot-at 2 -- --hwdec=no
"${case[@]}" --name gl-2d --api opengl --film "$fixtures/2d.mkv"
"${case[@]}" --name gl-sbs --api opengl --film "$fixtures/sbs.mkv"
"${case[@]}" --name a10-2d --a10 --film "$fixtures/2d.mkv"
"${case[@]}" --name a10-sbs --a10 --film "$fixtures/sbs.mkv" --screenshot-at 2
"${case[@]}" --name a10-sbs2 --a10 --film "$fixtures/sbs2.mkv"
"${case[@]}" --name a10-tb --a10 --film "$fixtures/tb.mkv"
"${case[@]}" --name a10-auto-copy --a10 --film "$fixtures/sbs.mkv" -- --hwdec=auto-copy
"${case[@]}" --name a10-vaapi-copy --a10 --film "$fixtures/2d.mkv" -- --hwdec=vaapi-copy
"${case[@]}" --name a10-record --a10 --machine-record true --film "$fixtures/sbs.mkv"
"${case[@]}" --name a10-record-no --a10 --machine-record false --film "$fixtures/2d.mkv"
"${case[@]}" --name null-2d --vo null --film "$fixtures/2d.mkv"
