#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# The independent reference on the analytic three-quad scene with its perspective in
# GL_MODELVIEW (tests/quads TEST_MODELVIEW_CAMERA), as Star Wars draws: each eye rendered
# alone by reference.c, packed side by side and measured by measure-quads.py. With no
# separation the same measurement must fail.
set -euo pipefail
cd /workspace/gl-stereo
make -s tests/quads
work=/build/reference-modelview; mkdir -p "$work"
gcc -shared -fPIC savers/audit/reference.c -o "$work/reference.so" -ldl -lGL -lm
Xvfb :91 -screen 0 1280x720x24 -ac -nolisten tcp > "$work/xvfb.log" 2>&1 & server=$!
trap 'kill $server' EXIT
sleep 1
export DISPLAY=:91 LIBGL_ALWAYS_SOFTWARE=1
for separation in 2 0; do
    for eye in left right; do
        rm -f "$work/$separation-$eye.ppm"
        AUDIT_FRAME=1 AUDIT_CAPTURE="$work/$separation-$eye.ppm" AUDIT_READY="$work/$separation-$eye.ready" AUDIT_REAL_TIME=1 \
            TEST_MODELVIEW_CAMERA=1 REFERENCE_EYE=$eye REFERENCE_SEPARATION=$separation \
            LD_PRELOAD="/build/fixture-egl.so:$work/reference.so" timeout 20 tests/quads > "$work/$separation-$eye.log" 2>&1 || true
        # the fixture stops the program once it has written the requested frame
        test -s "$work/$separation-$eye.ppm"
    done
    python3 - "$work/$separation-left.ppm" "$work/$separation-right.ppm" "$work/$separation-sbs.ppm" <<'PY'
import sys
from PIL import Image
left, right = Image.open(sys.argv[1]), Image.open(sys.argv[2])
pair = Image.new('RGB', (left.width * 2, left.height)); pair.paste(left, (0, 0)); pair.paste(right, (left.width, 0)); pair.save(sys.argv[3])
PY
    if python3 measure-quads.py "$work/$separation-sbs.ppm" 2 5; then
        test "$separation" = 2
    else
        test "$separation" = 0
    fi
done
echo 'PASS: the reference takes a camera from GL_MODELVIEW; without separation the measurement fails'
