#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
ulimit -c 0
test -e /.dockerenv
test "$(id -u)" != 0
repo=$PWD
run=$repo/out/plasma/rig-${RIG_NAME:-manual}
mkdir -p "$run/home" "$run/config" "$run/runtime"
chmod 700 "$run/runtime"
export HOME="$run/home" XDG_CONFIG_HOME="$run/config" XDG_RUNTIME_DIR="$run/runtime"
export XDG_DATA_DIRS="$repo/out/plasma/share:$repo/out/plasma/sdk/usr/share:/usr/share"
export XDG_CURRENT_DESKTOP=KDE QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software
export LP_NUM_THREADS=4
unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER
export QT_LOGGING_RULES="org.sparky.stereoshow.debug=true"
export GL_STEREO_PRIVATE_RIG=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export KWIN_COMPOSE=${RIG_COMPOSE:-O2} KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1
export LD_LIBRARY_PATH="$repo/out/plasma/prefix/lib:$repo/out/plasma/build"
unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD
if [[ -n ${RIG_MUTATION:-} ]]; then export LD_PRELOAD="$RIG_MUTATION"; fi
pids=()
cleanup() {
    for ((i=${#pids[@]}-1; i>=0; --i)); do kill "${pids[i]}" 2>/dev/null || true; done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
dbus-daemon --session --fork --print-address --print-pid >"$run/system-bus"
export DBUS_SYSTEM_BUS_ADDRESS=$(head -n1 "$run/system-bus")
pids+=("$(tail -n1 "$run/system-bus")")
export LD_LIBRARY_PATH="$repo/out/plasma/greeter-build/bin:$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu/qt6/plugins"
export QML_IMPORT_PATH="$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu/qt6/qml"
python3 plasma/fixture-services.py >"$run/services.log" 2>&1 & pids+=($!)
cp out/plasma/power-defaults/kscreenlockerrc "$XDG_CONFIG_HOME/kscreenlockerrc"
cp out/plasma/power-defaults/powerdevilrc "$XDG_CONFIG_HOME/powerdevilrc"
printf '[Greeter]\nWallpaperPlugin=org.kde.color\n' >>"$XDG_CONFIG_HOME/kscreenlockerrc"
if [[ ${RIG_KCM:-0} == 1 ]]; then
    cp plasma/stereoshowrc "$XDG_CONFIG_HOME/stereoshowrc"
else
    printf '[General]\nIdleSeconds=60\nCycleSeconds=600\n' >"$XDG_CONFIG_HOME/stereoshowrc"
fi
backend=(--virtual)
if [[ ${RIG_BACKEND:-virtual} == x11 ]]; then
    Xvfb :97 -screen 0 1280x720x24 -ac -nolisten tcp >"$run/xvfb.log" 2>&1 & pids+=($!)
    sleep 1
    backend=(--x11-display :97)
fi
"$repo/out/plasma/bin/kwin_wayland" "${backend[@]}" --width=${RIG_WIDTH:-640} --height=${RIG_HEIGHT:-360} --output-count=${RIG_OUTPUTS:-1} --socket=gl-stereo-wayland --no-global-shortcuts >"$run/kwin.log" 2>&1 & pids+=($!)
for attempt in {1..100}; do [[ -S $XDG_RUNTIME_DIR/gl-stereo-wayland ]] && break; sleep .1; done
[[ -S $XDG_RUNTIME_DIR/gl-stereo-wayland ]]
export WAYLAND_DISPLAY=gl-stereo-wayland
if [[ ${RIG_KCM:-0} == 1 ]]; then
    export QT_PLUGIN_PATH="$repo/out/plasma/greeter-build/bin:$QT_PLUGIN_PATH"
    kcmshell6 kcm_screenlocker >"$run/kcm.log" 2>&1 & pids+=($!)
elif [[ ${RIG_REAL_LOCK:-0} == 1 ]]; then
    "$repo/out/plasma/build/gl-stereo-show" >"$run/show.log" 2>&1 & pids+=($!)
    for attempt in {1..100}; do
        dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive >"$run/ready-lock.log" 2>&1 && break
        sleep .1
    done
    dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.Lock >"$run/lock.log"
    sleep 1
    dbus-send --session --print-reply --dest=org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive >>"$run/lock.log"
    grep -q 'boolean true' "$run/lock.log"
elif [[ ${RIG_GREETER:-0} == 1 ]]; then
    export LD_LIBRARY_PATH="$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
    export QT_PLUGIN_PATH="$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu/qt6/plugins"
    export QML_IMPORT_PATH="$repo/out/plasma/sdk/usr/lib/x86_64-linux-gnu/qt6/qml"
    "${RIG_GREETER_BINARY:-$repo/out/plasma/greeter-build/bin/kscreenlocker_greet}" --testing --immediateLock >"$run/greeter.log" 2>&1 & pids+=($!)
else
    "$repo/out/plasma/build/gl-stereo-show" >"$run/show.log" 2>&1 & pids+=($!)
fi
if [[ ${RIG_INHIBIT:-0} == 1 ]]; then
    "$repo/out/plasma/build/rig-inhibit" >"$run/inhibit.log" 2>&1 & inhibit_pid=$!; pids+=($inhibit_pid)
    sleep 65
    ! grep -q 'running true' "$run/show.log"
    timeout 10 "$repo/out/plasma/build/capture" "$run/inhibited.png" >>"$run/capture.log" 2>&1
    kill "$inhibit_pid"
    wait "$inhibit_pid" || true
fi
sleep "${RIG_SECONDS:-70}"
if [[ ${RIG_INPUT:-0} == 1 ]]; then
    "$repo/out/plasma/build/rig-input"
    sleep 2
fi
if [[ ${RIG_BACKEND:-virtual} == x11 ]]; then
    python3 - "$run/xvfb.png" <<'PYTHON'
from PIL import ImageGrab
import sys
ImageGrab.grab(xdisplay=':97').save(sys.argv[1])
PYTHON
fi
timeout 10 "$repo/out/plasma/build/capture" "$run/screen.png" >"$run/capture.log" 2>&1
timeout 10 "$repo/out/plasma/build/capture" "$run/window.png" window >>"$run/capture.log" 2>&1

if [[ ${RIG_LIFECYCLE:-0} == 1 ]]; then source plasma/rig-lifecycle.sh; fi

if [[ ${RIG_OUTPUTS:-1} == 2 ]]; then
    timeout 10 "$repo/out/plasma/build/capture" "$run/output-1.png" Virtual-0 >>"$run/capture.log" 2>&1
    timeout 10 "$repo/out/plasma/build/capture" "$run/output-2.png" Virtual-1 >>"$run/capture.log" 2>&1
fi
