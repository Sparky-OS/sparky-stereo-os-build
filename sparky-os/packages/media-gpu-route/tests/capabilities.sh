#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# Capability fixtures for media-gpu-route-query: Mesa's amdgpu drm-shim gives
# RADV a Renoir (GFX9: zero-copy import present) or a Stoney and a Polaris12
# (GFX8, like the A10's Carrizo: dma-buf without DRM format modifiers, so
# copy-only), with no device of the host. With a real render node (RENDER=1),
# the decoder choice is checked too: a copy-back caller keeps software unless
# allowed, an importing caller gets the hardware decoder.
# Usage: capabilities.sh QUERY [SHIM_LIBRARY]
set -u
query=$1
shim=${2:-/usr/lib/x86_64-linux-gnu/libamdgpu_noop_drm_shim.so}
failures=0
expect() {
    local name=$1 pattern=$2 output=$3
    if grep -qE -- "$pattern" <<<"$output"; then
        echo "ok   $name"
    else
        echo "FAIL $name: wanted /$pattern/ in:"; sed 's/^/     /' <<<"$output"
        failures=$((failures + 1))
    fi
}
export XDG_CONFIG_DIRS=/nonexistent XDG_CONFIG_HOME=/nonexistent
unset MEDIA_GPU_ROUTE_COPY_BACK
if [ -e "$shim" ] && [ ! -e /dev/dri/renderD128 ]; then
    out=$(AMDGPU_GPU_ID=renoir LD_PRELOAD=$shim "$query" --capabilities 2>&1)
    expect "zero-copy present: RADV Renoir (GFX9) imports" 'vulkan-import=yes' "$out"
    for chip in stoney polaris12; do
        out=$(AMDGPU_GPU_ID=$chip LD_PRELOAD=$shim "$query" --capabilities 2>&1)
        expect "copy-only: RADV $chip (GFX8) has no modifiers" 'vulkan-import=no' "$out"
        expect "copy-only: RADV $chip (GFX8) never imports" '^gpus=1 copy-back=not-allowed' "$out"
    done
    out=$("$query" --capabilities 2>&1)
    expect "none: no hardware GPU" '^gpus=0 copy-back=not-allowed' "$out"
    out=$("$query" --decoder h264 100 8 1920x1080 import 2>&1)
    expect "none: an importing caller learns nothing" '^result=unknown' "$out"
    out=$("$query" --decoder h264 100 8 1920x1080 copy 2>&1)
    expect "none: a copy-back caller keeps software" '^result=software' "$out"
fi
if [ "${RENDER:-0}" = 1 ]; then
    out=$("$query" --capabilities 2>&1)
    expect "real GPU: zero-copy import offered" 'vulkan-import=yes' "$out"
    out=$("$query" --decoder h264 100 8 1920x1080 copy 2>&1)
    expect "real GPU: copy-back caller keeps software by default" '^result=software' "$out"
    out=$("$query" --decoder h264 100 8 1920x1080 import 2>&1)
    expect "real GPU: importing caller gets VA-API" '^result=hardware backend=vaapi' "$out"
    out=$(MEDIA_GPU_ROUTE_COPY_BACK=true "$query" --decoder h264 100 8 1920x1080 copy 2>&1)
    expect "real GPU: copy-back allowed by the environment" '^result=hardware backend=vaapi' "$out"
    mkdir -p "${TMPDIR:-/tmp}/mgr-machine"
    printf '[Decoding]\nCopyBack=true\n' > "${TMPDIR:-/tmp}/mgr-machine/sparky-stereo-graphicsrc"
    out=$(XDG_CONFIG_DIRS="${TMPDIR:-/tmp}/mgr-machine" "$query" --decoder h264 100 8 1920x1080 copy 2>&1)
    expect "real GPU: copy-back allowed by the machine record" '^result=hardware backend=vaapi' "$out"
    out=$("$query" --decoder h264 110 10 1920x1080 import 2>&1)
    expect "real GPU: H.264 High 10 stays software" '^result=software' "$out"
fi
[ "$failures" = 0 ] && echo PASSED || echo "FAILED ($failures)"
exit $((failures != 0))
