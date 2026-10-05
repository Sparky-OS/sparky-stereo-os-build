#!/bin/bash
# usage: run-sub.sh <name> <installed|built> [client, default the subsurface test]
# A 2D window with a declared 3D subsurface, captured with KWin's ScreenShot2.
name=$1; which=$2; client=${3:-/s/test/egl-stereo-subsurface}; ev=/s/evidence/$name; mkdir -p $ev
export HOME=/s/home XDG_RUNTIME_DIR=/s/rt-$name LANG=C.UTF-8 LC_ALL=C.UTF-8
rm -rf $XDG_RUNTIME_DIR; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
KWIN=kwin_wayland
if [ "$which" = built ]; then
  export LD_LIBRARY_PATH=/s/build/bin QT_PLUGIN_PATH=/s/build/bin
  KWIN=/s/build/bin/kwin_wayland
fi
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1
dbus-run-session -- bash -c "
$KWIN --virtual --xwayland --socket=sub --width 1024 --height 640 > $ev/kwin.log 2>&1 & kp=\$!
for i in \$(seq 1 120); do test -S \$XDG_RUNTIME_DIR/sub && break; sleep .25; done; sleep 1
WAYLAND_DISPLAY=sub HOLD_SECONDS=8 EGL_STEREO_HOLD_SECONDS=8 $client > $ev/app.log 2>&1 & ap=\$!
sleep 3
QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=sub QT_CAPTURE_SCREEN=1 QT_CAPTURE_PNG=$ev/shot.png /q/qt-capture '' red,green nolabel > $ev/capture.log 2>&1
for i in 2 3 4 5 6; do sleep 0.4; QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=sub QT_CAPTURE_SCREEN=1 QT_CAPTURE_PNG=$ev/shot-\$i.png /q/qt-capture '' red,green nolabel >> $ev/capture-more.log 2>&1; done
wait \$ap; echo app_rc=\$? >> $ev/app.log
kill \$kp; wait \$kp 2>/dev/null"
rm -rf $XDG_RUNTIME_DIR
