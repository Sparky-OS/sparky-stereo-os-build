#!/bin/bash
# in the container: run a Marble application with a frozen clock; env: FLAVOR=stock|patched, APP=marble|marble-qt, STEREO=1 (sets the saved setting), PLAT=wayland|xcb
mkdir -p /tmp/home/.config
if [ "$APP" = marble-qt ]; then
  if [ -n "$STEREO" ]; then mkdir -p /tmp/home/.config/kde.org
    printf '[MainWindow]\nstereo3D=true\n' > /tmp/home/.config/kde.org/Marble\ Desktop\ Globe.conf; fi
else   # the KDE application: saved settings, PROJ = projection (7 = Perspective)
  { echo '[MarbleWidget]'; [ -n "$STEREO" ] && echo 'stereo3D=true'; [ -n "$PROJ" ] && echo "projection=$PROJ"; } > /tmp/home/.config/marblerc
fi
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1 FAKETIME="2026-10-07 12:00:00" FAKETIME_DONT_FAKE_MONOTONIC=1
export QT_QPA_PLATFORM=${PLAT:-wayland} WAYLAND_DEBUG=client LIBGL_ALWAYS_SOFTWARE=1 QT_LOGGING_RULES='*.debug=false;qt.qpa.*=false' LC_ALL=C.UTF-8
if [ "$FLAVOR" = patched ]; then
  export QT_PLUGIN_PATH=/inst/stereo/lib/plugins XDG_DATA_DIRS=/inst/stereo/share:/usr/share
  BIN=/inst/stereo/bin/$APP
else BIN=/usr/bin/$APP; fi   # stock and pkg: the installed packages
[ "$PLAT" = xcb ] && unset WAYLAND_DEBUG
exec $BIN $ARGS 2>&1 | grep --line-buffered -E "kde_stereo_content_v1|kde_stereo_content_manager_v1#.*create|get_subsurface|place_below|rror|arning" 
