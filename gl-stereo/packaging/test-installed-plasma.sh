#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
source=${1:?source checkout}
command -v kcmshell6 >/dev/null
cd /build/installed-tests
# The receiver and producers remain installed binaries. Only their input
# catalogue is a deterministic fixture, restored even when an assertion fails.
catalogue=/usr/share/gl-stereo/catalogue.json
test -w "$catalogue"
cp "$catalogue" installed-catalogue.saved.json
trap 'cp installed-catalogue.saved.json "$catalogue"' EXIT
python3 - "$catalogue" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
star = next(entry for entry in json.loads(path.read_text()) if entry['id'] == 'starfield')
star['command'] += ['--oracle', '--oracle-x', '-.7']
path.write_text(json.dumps([star], indent=2) + '\n')
PY
mkdir -p out/plasma/{build,bin,power-defaults}
cp "$source"/plasma/{rig.sh,rig-lifecycle.sh,fixture-services.py,check-eyes.py,check-defaults.py,old-output.c} plasma/
cp /etc/xdg/stereoshowrc plasma/stereoshowrc
cp /etc/xdg/{powerdevilrc,kscreenlockerrc} out/plasma/power-defaults/
python3 plasma/check-defaults.py out/plasma/power-defaults
# Only capture/input fixtures are local; production paths resolve into /usr.
ln -sf /usr/bin/kwin_wayland out/plasma/bin/kwin_wayland
ln -sf /usr/bin/gl-stereo-show out/plasma/build/gl-stereo-show
for name in capture rig-input rig-inhibit; do ln -sf "$PWD/native/$name" "out/plasma/build/$name"; done
# The original rig's SDK search directories do not exist in this fixture.
# Remove those overrides so Qt, KDE, the theme and libraries come from /usr.
python3 - <<'PY'
from pathlib import Path
p = Path('plasma/rig.sh')
s = p.read_text()
s = '\n'.join(line for line in s.splitlines() if not line.lstrip().startswith((
    'export LD_LIBRARY_PATH=', 'export QT_PLUGIN_PATH=', 'export QML_IMPORT_PATH=', 'export XDG_DATA_DIRS=')))+'\n'
s = s.replace('unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD', 'unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD LD_LIBRARY_PATH QT_PLUGIN_PATH QML_IMPORT_PATH\nexport XDG_DATA_DIRS=/usr/share')
p.write_text(s)
PY
export RIG_WIDTH=1280 RIG_HEIGHT=720
RIG_NAME=installed-idle RIG_LIFECYCLE=1 RIG_SECONDS=65 dbus-run-session -- bash plasma/rig.sh
for name in window restored awake; do python3 plasma/check-eyes.py "out/plasma/rig-installed-idle/$name.png"; done
RIG_NAME=installed-lock RIG_REAL_LOCK=1 RIG_LIFECYCLE=1 RIG_INPUT=1 RIG_SECONDS=8 dbus-run-session -- bash plasma/rig.sh
for name in window restored; do python3 plasma/check-eyes.py "out/plasma/rig-installed-lock/$name.png" --prompt; done
python3 plasma/check-eyes.py out/plasma/rig-installed-lock/awake.png
RIG_NAME=installed-inhibit RIG_INHIBIT=1 RIG_SECONDS=65 dbus-run-session -- bash plasma/rig.sh
python3 plasma/check-eyes.py out/plasma/rig-installed-inhibit/window.png
RIG_NAME=installed-outputs RIG_REAL_LOCK=1 RIG_OUTPUTS=2 RIG_INPUT=1 RIG_SECONDS=8 dbus-run-session -- bash plasma/rig.sh
for name in 1 2; do python3 plasma/check-eyes.py "out/plasma/rig-installed-outputs/output-$name.png"; done
RIG_NAME=installed-kcm RIG_KCM=1 RIG_SECONDS=4 dbus-run-session -- bash plasma/rig.sh
! grep -E 'Type .* unavailable|ReferenceError|is not installed|Error loading' out/plasma/rig-installed-kcm/kcm.log
gcc -shared -fPIC plasma/old-output.c -o out/plasma/old-output.so
RIG_NAME=installed-old-idle RIG_MUTATION="$PWD/out/plasma/old-output.so" RIG_SECONDS=65 dbus-run-session -- bash plasma/rig.sh
if python3 plasma/check-eyes.py out/plasma/rig-installed-old-idle/window.png; then exit 1; fi
RIG_NAME=installed-old-lock RIG_MUTATION="$PWD/out/plasma/old-output.so" RIG_REAL_LOCK=1 RIG_INPUT=1 RIG_SECONDS=8 dbus-run-session -- bash plasma/rig.sh
if python3 plasma/check-eyes.py out/plasma/rig-installed-old-lock/window.png --prompt; then exit 1; fi
printf 'PASS: installed Plasma idle, lock, lifecycle, inhibit, outputs, settings and old-output mutations\n'
