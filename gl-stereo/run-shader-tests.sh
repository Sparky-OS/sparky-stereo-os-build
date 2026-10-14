#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
mkdir -p out/shader/{perspective,orthographic}
for mode in perspective orthographic; do
    # Repeated runs must never reuse a diagnostic frame.
    find "out/shader/$mode" -maxdepth 1 -name 'frame-*' -type f -delete
    flags=()
    [[ $mode == orthographic ]] && flags+=(TEST_ORTHO=1)
    env "${flags[@]}" LD_PRELOAD="${GL_STEREO_TEST_LIBRARY:-$PWD/libgl-stereo.so}" GL_STEREO=1 GL_STEREO_DUMP=1 \
        GL_STEREO_DUMP_DIR="$PWD/out/shader/$mode" ./tests/shader-quads
    separation=2
    [[ $mode == orthographic ]] && separation=0
    python3 measure-quads.py "out/shader/$mode/"*.ppm "$separation" 5
done
printf 'PASS: unchanged shader sources, restored uniforms, analytic perspective and zero-parallax orthographic cameras\n'
