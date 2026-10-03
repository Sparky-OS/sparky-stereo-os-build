#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
mkdir -p out/synthetic out/hacks
make -j4
./run-synthetic-tests.sh | tee out/synthetic/results.txt
env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 ./tests/state | tee out/state.txt
mkdir -p out/egl-damage
rm -f out/egl-damage/frame-*
env LD_PRELOAD="$PWD/libgl-stereo.so" GL_STEREO=1 GL_STEREO_DUMP=2 GL_STEREO_DUMP_DIR="$PWD/out/egl-damage" ./tests/egl-damage
python3 - <<'PYTHON'
from PIL import Image
from pathlib import Path
import numpy as np
p = sorted(Path('out/egl-damage').glob('*.ppm'))[-1]
a = np.array(Image.open(p))
assert a.shape == (100,320,3)
assert a.std() > 10 and np.array_equal(a[:,:160],a[:,160:])
assert np.array_equal(a[50,80],[255,0,0]) and np.array_equal(a[0,0],[0,0,0])
Image.open(p).save('out/egl-damage/verified.png')
PYTHON
./run-hack-tests.sh | tee out/hacks/results.txt
./run-native-tests.sh | tee out/native-results.txt
python3 tests/launcher.py | tee out/launcher-results.txt
python3 tests/settings-dialog.py | tee out/launcher/dialog-results.txt
make install DESTDIR="$PWD/out/install"
test -x out/install/usr/bin/gl-stereo-run
printf 'PASS: all functional checks and staged install\n'
