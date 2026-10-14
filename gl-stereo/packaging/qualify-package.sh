#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
repo=$PWD
stage=$repo/debian
work=$stage/qualification
mkdir -p "$work"/{savers,tests,out/bin}
cp tests/{starfield,rocks,qualify-savers}.py "$work/tests/"
cp savers/{frames,catalogue}.py "$work/savers/"
cp measure-hack.py "$work/"
cp tests/announce "$work/tests/"
ln -sf "$stage/gl-stereo/usr/lib/gl-stereo/libgl-stereo.so" "$work/libgl-stereo.so"
ln -sf "$stage/gl-stereo-savers/usr/lib/gl-stereo/savers/starfield" "$work/savers/starfield"
ln -sf /usr/libexec/xscreensaver/rocks "$work/out/bin/rocks"
cd "$work"
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=4
unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD GL_STEREO
xvfb-run -a -s '-screen 0 2560x1440x24 -ac -nolisten tcp' bash -euc '
python3 tests/starfield.py
python3 tests/rocks.py
python3 tests/qualify-savers.py'
python3 - "$stage/gl-stereo-savers/usr/share/gl-stereo/catalogue.json" <<'PY'
import json
from pathlib import Path
import sys
entries = json.loads(Path('out/eligibility/catalogue.json').read_text())
assert {e['id'] for e in entries} == {'starfield','rocks','gears','molecule','rubik'}, entries
for entry in entries:
    if entry['id'] == 'starfield':
        entry['command'][0] = '/usr/lib/gl-stereo/savers/starfield'
    entry['library'] = '/usr/lib/gl-stereo/libgl-stereo.so'
    if 'LD_PRELOAD' in entry['environment']:
        entry['environment']['LD_PRELOAD'] = entry['library']
output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(entries, indent=2)+'\n')
PY

# The full milestone manifest is produced by installed-file audits. The
# bootstrap build keeps the accepted five until that manifest exists.
if [ -f "$repo/savers/qualification-6.09.json" ]; then
    python3 "$repo/savers/install-qualified.py" "$repo/savers/qualification-6.09.json" \
        "$stage/gl-stereo-savers/usr/share/gl-stereo/catalogue.json" \
        "$stage/gl-stereo/usr/lib/gl-stereo/libgl-stereo.so"
fi
python3 "$repo/savers/make-index.py" "$stage/gl-stereo-savers/usr/share/gl-stereo/savers.json" \
    "$stage/gl-stereo-savers/usr/share/gl-stereo/catalogue.json"
