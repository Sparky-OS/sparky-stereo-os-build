#!/bin/sh
sleep 4
[ -n "${CLIENT_LD_LIBRARY_PATH:-}" ] && export LD_LIBRARY_PATH=$CLIENT_LD_LIBRARY_PATH
env_x=""
if [ "$PLATFORM" = x11 ]; then
  export DISPLAY=$(ls /tmp/.X11-unix 2>/dev/null | head -1 | sed 's/^X/:/'); export SDL_VIDEODRIVER=x11; unset WAYLAND_DISPLAY
else
  export WAYLAND_DISPLAY=w SDL_VIDEODRIVER=wayland; unset DISPLAY
fi
case "$PATHMODE" in
  shim) GS="gl-stereo-run --nvidia-opengl nvidia --" ;;
  zink) GS="gl-stereo-run --nvidia-opengl zink --" ;;
  zinkraw) export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json:/usr/share/glvnd/egl_vendor.d/10_nvidia.json __GLX_VENDOR_LIBRARY_NAME=mesa MESA_LOADER_DRIVER_OVERRIDE=zink; GS="" ;;
  *) GS="" ;;
esac
$GS $PROG $SECS > /tmp/client.$$.log 2>&1 &
CP=$!
sleep 6
python3 /rig/check.py ${OUTPNG:-} 2>&1 | tail -3
grep RESULT /tmp/client.$$.log
[ -n "${MAPS:-}" ] && { grep -E "${MAPSRE:-GLX_mesa|gallium|zink_dri|libEGL_mesa}" /proc/$CP/maps | awk "{print \$6}" | sort -u; }
[ -n "${SHOWLOG:-}" ] && tail -${TAILN:-20} /tmp/client.$$.log
[ -n "${SAVELOG:-}" ] && cp /tmp/client.$$.log /out/${SAVELOG}
kill $CP 2>/dev/null; wait $CP 2>/dev/null
