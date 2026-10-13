#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
ulimit -c 0
test -e /.dockerenv
test "$(id -u)" != 0
unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD
repo=$PWD
cleanup() {
    python3 -c 'from pathlib import Path; Path("out/plasma/kscreenlocker-v6.7.4/autotests/data/test_service").unlink(missing_ok=True)'
}
trap cleanup EXIT
export HOME="$repo/out/home" LP_NUM_THREADS=4
mkdir -p "$HOME" out/plasma/bin
cp /usr/bin/kwin_wayland out/plasma/bin/kwin_wayland
python3 plasma/check-defaults.py out/plasma/power-defaults
python3 - <<'PY'
import json, sys
sys.path.insert(0, 'savers')
from catalogue import load
entries = load('out/eligibility/catalogue.json')
star = next(entry for entry in entries if entry['id'] == 'starfield')
star['command'] += ['--oracle', '--oracle-x', '-.7']
json.dump([star], open('out/plasma/oracle.json','w'), indent=2)
PY
# Build the production receiver first, then the deterministic camera fixture.
bash plasma/build.sh >out/plasma/verify-build.log 2>&1
cmake -S plasma -B out/plasma/build -DSAVER_CATALOGUE="$repo/out/plasma/oracle.json" >>out/plasma/verify-build.log 2>&1
cmake --build out/plasma/build -j4 >>out/plasma/verify-build.log 2>&1
bash plasma/build-greeter.sh >out/plasma/verify-greeter.log 2>&1
export PKG_CONFIG_PATH="$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu/pkgconfig"
cmake -S out/plasma/kscreenlocker-v6.7.4 -B out/plasma/greeter-build -DBUILD_TESTING=ON -DCMAKE_INSTALL_LIBEXECDIR="$repo/out/plasma/greeter-build/bin" >>out/plasma/verify-greeter.log 2>&1
cmake --build out/plasma/greeter-build -j4 >>out/plasma/verify-greeter.log 2>&1
export LD_LIBRARY_PATH="$repo/out/plasma/prefix/lib:$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu"
ctest --test-dir out/plasma/build --output-on-failure
sed "s|/usr/lib/x86_64-linux-gnu/pam_wrapper/|$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu/pam_wrapper/|g" out/plasma/greeter-build/autotests/test_service >out/plasma/kscreenlocker-v6.7.4/autotests/data/test_service
QT_QPA_PLATFORM=offscreen dbus-run-session -- ctest --test-dir out/plasma/greeter-build -R 'ksmserver-(pam|logind)Test' --output-on-failure
rm out/plasma/kscreenlocker-v6.7.4/autotests/data/test_service
cmake -S plasma/settings-test -B out/plasma/settings-test -G Ninja -DSETTINGS_DIR="$repo/out/plasma/greeter-build/settings" >out/plasma/verify-settings.log 2>&1
cmake --build out/plasma/settings-test -j4 >>out/plasma/verify-settings.log 2>&1
mkdir -p out/plasma/verify-settings-config
XDG_CONFIG_HOME="$repo/out/plasma/verify-settings-config" dbus-run-session -- out/plasma/settings-test/settings-test
python3 plasma/transport-probe.py out/plasma/oracle.json out/plasma/verify-transport.png
python3 plasma/check-eyes.py out/plasma/verify-transport.png
# Each invocation owns new buses, sockets, Xvfb and KWin processes.
export RIG_WIDTH=1280 RIG_HEIGHT=720
RIG_NAME=verify-idle RIG_LIFECYCLE=1 RIG_SECONDS=65 dbus-run-session -- bash plasma/rig.sh
python3 plasma/check-eyes.py out/plasma/rig-verify-idle/window.png
python3 plasma/check-eyes.py out/plasma/rig-verify-idle/restored.png
python3 plasma/check-eyes.py out/plasma/rig-verify-idle/awake.png
RIG_NAME=verify-lock RIG_REAL_LOCK=1 RIG_LIFECYCLE=1 RIG_INPUT=1 RIG_SECONDS=8 dbus-run-session -- bash plasma/rig.sh
python3 plasma/check-eyes.py out/plasma/rig-verify-lock/window.png --prompt
python3 plasma/check-eyes.py out/plasma/rig-verify-lock/restored.png --prompt
python3 plasma/check-eyes.py out/plasma/rig-verify-lock/awake.png
python3 - <<'PY'
from PIL import Image
for name in ('battery','producer-failed'):
    image = Image.open('out/plasma/rig-verify-lock/'+name+'.png').convert('RGB')
    assert image.size == (1280,720), (name, image.size)
    assert image.getextrema() != ((0,0),(0,0),(0,0)), 'missing static greeter fallback'
assert Image.open('out/plasma/rig-verify-idle/dismissed.png').size == (1280,720)
print('PASS: battery and failed-producer fallback; idle input dismissal')
PY
RIG_NAME=verify-inhibit RIG_INHIBIT=1 RIG_SECONDS=65 dbus-run-session -- bash plasma/rig.sh
python3 plasma/check-eyes.py out/plasma/rig-verify-inhibit/window.png
RIG_NAME=verify-outputs RIG_REAL_LOCK=1 RIG_OUTPUTS=2 RIG_INPUT=1 RIG_SECONDS=8 dbus-run-session -- bash plasma/rig.sh
python3 plasma/check-eyes.py out/plasma/rig-verify-outputs/output-1.png
python3 plasma/check-eyes.py out/plasma/rig-verify-outputs/output-2.png
RIG_NAME=verify-kcm RIG_KCM=1 RIG_SECONDS=4 dbus-run-session -- bash plasma/rig.sh
! grep -E 'Type .* unavailable|ReferenceError|is not installed|Error loading' out/plasma/rig-verify-kcm/kcm.log
gcc -shared -fPIC plasma/old-output.c -o out/plasma/old-output.so
RIG_NAME=verify-old-idle RIG_MUTATION="$repo/out/plasma/old-output.so" RIG_SECONDS=65 dbus-run-session -- bash plasma/rig.sh
if python3 plasma/check-eyes.py out/plasma/rig-verify-old-idle/window.png >out/plasma/verify-old-idle-rejected.log 2>&1; then exit 1; fi
RIG_NAME=verify-old-lock RIG_MUTATION="$repo/out/plasma/old-output.so" RIG_REAL_LOCK=1 RIG_INPUT=1 RIG_SECONDS=8 dbus-run-session -- bash plasma/rig.sh
if python3 plasma/check-eyes.py out/plasma/rig-verify-old-lock/window.png --prompt >out/plasma/verify-old-lock-rejected.log 2>&1; then exit 1; fi
echo 'PASS: both idle and real-lock captures reject the undeclared old output'
cmake -S plasma -B out/plasma/package-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$repo/out/plasma/prefix" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_SYSCONFDIR=/etc >out/plasma/verify-install.log 2>&1
cmake --build out/plasma/package-build -j4 >>out/plasma/verify-install.log 2>&1
DESTDIR="$repo/out/plasma/stage" cmake --install out/plasma/package-build >>out/plasma/verify-install.log 2>&1
make install install-savers install-catalogue DESTDIR="$repo/out/plasma/stage" >>out/plasma/verify-install.log 2>&1
python3 - <<'PY'
import hashlib, json
from pathlib import Path
stage = Path('out/plasma/stage')
for entry in json.loads((stage/'usr/share/gl-stereo/catalogue.json').read_text()):
    for key, proof in [('library','library_sha256'), ('command','executable_sha256')]:
        path = Path(entry[key][0] if key == 'command' else entry[key])
        candidate = stage / path.relative_to('/')
        if not candidate.exists(): candidate = path
        assert hashlib.sha256(candidate.read_bytes()).hexdigest() == entry[proof]
assert (stage/'etc/xdg/autostart/org.sparky.stereoshow.desktop').is_file()
assert (stage/'etc/xdg/stereoshowrc').read_bytes() == Path('plasma/stereoshowrc').read_bytes()
assert (stage/'usr/bin/gl-stereo-show').is_file()
print('PASS: staged native install and relocated hash-validated catalogue')
PY
echo 'PASS: Plasma integration suite'
