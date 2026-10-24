#!/bin/sh
set -eu
unset __EGL_VENDOR_LIBRARY_FILENAMES MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME
export WAYLAND_DISPLAY=order223-route
if [ "${ROUTE_INSTALLED:-0}" = 1 ]; then
 unset LD_LIBRARY_PATH
 /usr/bin/media-gpu-route-query > /w/logs/$SCENARIO-route.log
 /w/device-choice > /w/logs/$SCENARIO-after.log 2>&1
 printf '0\n' > /w/logs/$SCENARIO-after.exit
 exit 0
fi
/w/route-build/media-gpu-route-query > /w/logs/$SCENARIO-route.log
set +e
env -u LD_LIBRARY_PATH /w/device-choice > /w/logs/$SCENARIO-before.log 2>&1
printf '%s\n' "$?" > /w/logs/$SCENARIO-before.exit
LD_LIBRARY_PATH=/w/placebo-build/src /w/device-choice > /w/logs/$SCENARIO-after.log 2>&1
code=$?
printf '%s\n' "$code" > /w/logs/$SCENARIO-after.exit
set -e
[ "$code" = 0 ]
