#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
SO=$PWD/libgl-stereo.so
unset GL_STEREO_CLASS
mkdir -p out/quad out/quad-gears out/paraview
rm -f out/quad/frame-* out/quad-gears/frame-* out/paraview/frame-*
env LD_PRELOAD="$SO" GL_STEREO=1 ./tests/quad unsupported
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_DUMP=1 GL_STEREO_DUMP_DIR="$PWD/out/quad" ./tests/quad
env LD_PRELOAD="$SO" GL_STEREO=1 ./tests/quad fbconfig
env LD_PRELOAD="$SO" GL_STEREO=1 ./tests/quad minimum-depth
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=scientific GL_STEREO_RENDER_RESOLUTION=400x240 ./tests/quad visual
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=game ./tests/quad fbconfig
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=game ./tests/quad auto
env LD_PRELOAD="$SO" GL_STEREO=1 ./tests/quad auto
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=unknown ./tests/quad visual
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=unknown ./tests/quad auto
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=scientific ./tests/quad auto
env LD_PRELOAD="$SO" GL_STEREO=1 ./tests/draw-commands
rc=0
./tests/announce timeout --foreground 4 env LD_PRELOAD="$SO" GL_STEREO=1 \
    GL_STEREO_DUMP=30 GL_STEREO_DUMP_DIR="$PWD/out/quad-gears" glxgears -stereo -geometry 640x360 \
    > out/quad-gears/stdout.txt 2> out/quad-gears/stderr.txt || rc=$?
[ "$rc" = 124 ] || [ "$rc" = 0 ]
python3 measure-hack.py out/quad-gears --native-gears
./tests/announce timeout --foreground 45 env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_CLASS=scientific \
    GL_STEREO_DUMP=3 GL_STEREO_DUMP_DIR="$PWD/out/paraview" pvpython --force-onscreen-rendering \
    --opengl-window-backend=GLX --stereo --stereo-type='Crystal Eyes' tests/paraview-stereo.py \
    > out/paraview/stdout.txt 2> out/paraview/stderr.txt
if [ -s out/paraview/stderr.txt ]; then
    cat out/paraview/stderr.txt >&2
    exit 1
fi
python3 tests/check-native.py out/paraview
python3 - <<'PY'
from PIL import Image
from pathlib import Path
import numpy as np
p = sorted(Path('out/quad').glob('*.ppm'))[-1]
a = np.array(Image.open(p))
assert a.shape == (200,640,3)
for eye in range(2):
    expected = np.zeros((200,320,3),dtype=np.uint8)
    expected[:] = [0,255,255] if eye else [255,0,0]
    expected[200-130:200-70,120:200] = [255,255,0] if eye else [0,0,255]
    assert np.array_equal(a[:,eye*320:(eye+1)*320], expected)
Image.open(p).save('out/quad/verified.png')
print('PASS: exact per-eye native buffer images')
PY
