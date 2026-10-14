#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
SO=${GL_STEREO_TEST_LIBRARY:-$PWD/libgl-stereo.so}
D=$PWD/out/synthetic
mkdir -p "$D"
for t in quads quads-dlist quads-xform; do
    mkdir -p "$D/$t"
    rm -f "$D/$t"/frame-*.ppm
    env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_SEPARATION=2 GL_STEREO_CONVERGENCE=5 \
        GL_STEREO_DUMP=1 GL_STEREO_DUMP_DIR="$D/$t" "./tests/$t"
    python3 measure-quads.py "$D/$t/"*.ppm 2 5
done
for c in 5 10; do
    mkdir -p "$D/conv$c"
    rm -f "$D/conv$c"/frame-*.ppm
    env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_SEPARATION=2 GL_STEREO_CONVERGENCE="$c" \
        GL_STEREO_DUMP=1 GL_STEREO_DUMP_DIR="$D/conv$c" ./tests/quads
    python3 measure-quads.py "$D/conv$c/"*.ppm 2 "$c" 2.5,5,10
done
for mode in matrix texture zero ortho projection-view projection-rotate modelview-camera camera-texture; do
    dir="$D/$mode"
    mkdir -p "$dir"
    rm -f "$dir"/frame-*.ppm
    extra=()
    sep=2
    case "$mode" in
        matrix) extra=(TEST_MATRIX=1);;
        projection-view) extra=(TEST_PROJECTION_VIEW=1);;
        projection-rotate) extra=(TEST_PROJECTION_ROTATE=1);;
        modelview-camera) extra=(TEST_MODELVIEW_CAMERA=1);;
        camera-texture) extra=(TEST_CAMERA_TEXTURE=1);;
        texture) extra=(TEST_TEXTURE=1);;
        zero) sep=0;;
        ortho) extra=(TEST_ORTHO=1); sep=0;;
    esac
    # Orthographic projection must ignore even nonzero stereo separation.
    input_sep=$sep
    [ "$mode" != ortho ] || input_sep=2
    env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_SEPARATION="$input_sep" GL_STEREO_CONVERGENCE=5 \
        GL_STEREO_DUMP=1 GL_STEREO_DUMP_DIR="$dir" "${extra[@]}" ./tests/quads
    python3 measure-quads.py "$dir/"*.ppm "$sep" 5
done
./tests/quads "$D/mono.ppm"
env LD_PRELOAD="$SO" GL_STEREO=0 ./tests/quads "$D/disabled.ppm"
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_PASSTHROUGH=1 ./tests/quads "$D/passthrough.ppm"
cmp "$D/mono.ppm" "$D/disabled.ppm"
cmp "$D/mono.ppm" "$D/passthrough.ppm"
python3 - "$D" <<'PY'
from PIL import Image
import numpy as np
from pathlib import Path
import sys
p = Path(sys.argv[1])
mono = np.array(Image.open(p/'mono.ppm'))
zero = np.array(Image.open(next((p/'zero').glob('*.ppm'))))
assert np.array_equal(mono, zero[:, :640])
assert np.array_equal(mono, zero[:, 640:])
for path in p.glob('*/*.ppm'):
    Image.open(path).save(path.with_suffix('.png'))
image = np.array(Image.open(next((p/'quads').glob('*.ppm'))))
image[:, :640] = 0
Image.fromarray(image).save(p/'empty-mutant.png')
print('PASS: disabled, passthrough and zero-separation pixel identity')
PY
if python3 measure-quads.py "$D/empty-mutant.png" 2 5; then
    echo 'FAIL: empty-eye mutation accepted' >&2; exit 1
fi
mkdir -p "$D/swap-mutant"
rm -f "$D/swap-mutant"/frame-*.ppm
env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_SWAP=1 GL_STEREO_SEPARATION=2 GL_STEREO_CONVERGENCE=5 \
    GL_STEREO_DUMP=1 GL_STEREO_DUMP_DIR="$D/swap-mutant" ./tests/quads
if python3 measure-quads.py "$D/swap-mutant/"*.ppm 2 5; then
    echo 'FAIL: reversed-eye mutation accepted' >&2; exit 1
fi
echo 'PASS: empty-eye and reversed-eye mutations rejected'
mkdir -p "$D/multiframe"
rm -f "$D/multiframe"/frame-* "$D/dispatch.json"
env TEST_FRAMES=1 LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_DUMP=30 \
    GL_STEREO_DUMP_DIR="$D/multiframe" GL_STEREO_STATS="$D/dispatch.json" ./tests/quads
python3 measure-quads.py "$D/multiframe/"*.ppm 2 5
python3 - "$D/dispatch.json" <<'PY'
import json,sys
value = json.load(open(sys.argv[1]))
assert value == {'logical':160, 'issued':320}, value
print('PASS: exactly two dispatches per logical clear/draw across 40 frames')
PY
