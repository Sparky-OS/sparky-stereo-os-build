#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
source=${1:?source checkout or unpacked source package}
work=/build/installed-tests
mkdir -p "$work"/{out/bin,out/eligibility,plasma,tests,savers,fixtures}
cd "$work"
cp "$source"/{Makefile,run-synthetic-tests.sh,run-shader-tests.sh,run-hack-tests.sh,run-native-tests.sh,measure-hack.py,measure-quads.py} .
cp "$source"/tests/*.{c,py} tests/
# Build only test programs. Every production executable is an installed file.
for name in egl-damage state announce quad quads quads-dlist quads-xform shader-quads; do
    make "tests/$name"
done
ln -sf /usr/lib/gl-stereo/libgl-stereo.so libgl-stereo.so
ln -sf /usr/bin/gl-stereo-run gl-stereo-run
for name in starfield announce controller.py frames.py catalogue.py preferences.py settings.py strings.json; do
    ln -sf "/usr/lib/gl-stereo/savers/$name" "savers/$name"
done
ln -sf /usr/libexec/xscreensaver/rocks out/bin/rocks
cp /usr/share/gl-stereo/catalogue.json out/eligibility/catalogue.json
gcc -O2 -Wall -Wextra tests/window-sizing.c -o out/window-sizing-client -lGL -lX11 -ldl
export HOME="$work/out/home" LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=4
mkdir -p "$HOME"
unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD GL_STEREO
xvfb-run -a -s '-screen 0 2560x1440x24 -ac -nolisten tcp' bash -euc '
for version in 0 1 2; do
    LD_PRELOAD=/usr/lib/gl-stereo/libgl-stereo.so GL_STEREO=1 TEST_SUPPORT_VERSION=$version out/window-sizing-client
done
./run-synthetic-tests.sh
./run-shader-tests.sh
LD_PRELOAD=/usr/lib/gl-stereo/libgl-stereo.so GL_STEREO=1 tests/state
mkdir -p out/egl-damage
LD_PRELOAD=/usr/lib/gl-stereo/libgl-stereo.so GL_STEREO=1 GL_STEREO_DUMP=2 GL_STEREO_DUMP_DIR="$PWD/out/egl-damage" tests/egl-damage
./run-hack-tests.sh
./run-native-tests.sh
for profile in none game scientific unknown; do
    for mode in visual fbconfig auto; do
        LD_PRELOAD=/usr/lib/gl-stereo/libgl-stereo.so GL_STEREO=1 GL_STEREO_CLASS=$profile TEST_PRESET_CLASS=1 tests/quad $mode
    done
done
python3 tests/launcher.py
python3 tests/settings-dialog.py
python3 tests/saver-preferences.py
python3 tests/saver-frames.py
python3 tests/starfield.py
python3 tests/rocks.py
python3 tests/rotation.py'
python3 tests/display-pipe.py
python3 - <<'PY'
from pathlib import Path
from PIL import Image
import numpy as np
import sys
sys.path.insert(0, 'savers')
from catalogue import load
import json
entries = load('/usr/share/gl-stereo/catalogue.json')
index = json.loads(Path('/usr/share/gl-stereo/savers.json').read_text())
expected = {entry['id'] for entry in index if entry['kind']=='hack'}
assert len(expected)==132 and {e['id'] for e in entries}==expected
a = np.array(Image.open(sorted(Path('out/egl-damage').glob('*.ppm'))[-1]))
assert a.shape == (100,320,3)
assert a.std()>10 and np.array_equal(a[:,:160],a[:,160:])
assert np.array_equal(a[50,80],[255,0,0]) and np.array_equal(a[0,0],[0,0,0])
print('PASS: installed catalogue hashes and EGL damage pixels')
PY
for name in policytest frameclienttest nativeframetest capture rig-inhibit; do cp "$source/plasma/$name.cpp" fixtures/; done
cp "$source/plasma/rig-input.c" fixtures/
cmake -S "$source/packaging/installed-tests" -B native -G Ninja -DFIXTURES="$work/fixtures"
cmake --build native -j4
ctest --test-dir native --output-on-failure
printf 'PASS: installed layer, savers, launcher and native library regressions\n'
