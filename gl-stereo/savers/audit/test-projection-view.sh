#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
cd /workspace/gl-stereo
for version in before after; do
    directory=/build/projection-$version
    mkdir -p "$directory"
    library=$PWD/libgl-stereo.so
    [ "$version" = before ] || library=/build/projection-view.so
    env -u GL_STEREO_CONVERGENCE TEST_PROJECTION_VIEW=1 LD_PRELOAD="$library" GL_STEREO=1 GL_STEREO_DUMP=1 GL_STEREO_DUMP_DIR="$directory" tests/quads
    if python3 measure-quads.py "$directory/"*.ppm 2 5; then
        test "$version" = after
    else
        test "$version" = before
    fi
done
