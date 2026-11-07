#!/bin/sh
sleep 4
[ -n "${CLIENT_LD_LIBRARY_PATH:-}" ] && export LD_LIBRARY_PATH=$CLIENT_LD_LIBRARY_PATH
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
i=0
while [ $i -lt $K ]; do
  i=$((i+1))
  $GS $PROG 30 > /tmp/client.$$.$i.log 2>&1 &
  CP=$!
  sleep ${WAITS:-4}
  v=$(python3 /rig/check.py 2>&1 | sed -n 's/.*"verdict": "\([A-Z-]*\)".*/\1/p')
  echo "client $i ${v:-NOCHECK} $(grep -h -E "RESULT|zink through|gl-stereo:" /tmp/client.$$.$i.log | tr "\n" " " | cut -c1-230)"
  kill $CP 2>/dev/null; wait $CP 2>/dev/null
  sleep 1
done
