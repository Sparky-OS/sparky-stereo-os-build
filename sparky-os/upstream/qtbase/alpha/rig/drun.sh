#!/bin/bash
# Run one capture case in a proof image (Claude Sonnet, qtbase lane, 2026-10-07).
# usage: [IMG=qtbase-proof:ours] [SOFT=1] [PLAT=wayland|xcb] [SIZE=1280x800] [WAIT=5] [CSD=1] [NODECO=1] drun.sh <case> <client...>
#   SOFT=1  software GL for the client (KWin stays on the GPU); CSD=1 leaves Qt's client decorations enabled;
#   NODECO=1 KWin loads no decoration plugin (the compositor draws none, so Qt falls back to its own with CSD=1).
# Evidence lands in $EVROOT/<case>.
here=$(cd "$(dirname "$0")" && pwd)
case_=$1; shift
EVROOT=${EVROOT:-/K3D/temp/qtbase-pkg/evidence}
ev=$EVROOT/$case_
rm -rf "$ev"; mkdir -p "$ev"
uid=$(id -u); gid=$(id -g)
exec docker run --rm --platform linux/amd64 --cpus 4 --cap-add SYS_NICE \
  --device /dev/dri/renderD128 --group-add 125 --user $uid:$gid \
  -e KWIN_WAYLAND_NO_PERMISSION_CHECKS -e NODECO -e CSD -e SOFT -e PLAT -e SIZE -e WAIT -e SHIM -e MYQT -e CLIENT_ENV -e RUN_UID=$uid -e RUN_GID=$gid \
  -e QT_STEREO_WIDTH -e QT_STEREO_HEIGHT -e QT_STEREO_HOLD_MS -e QT_STEREO_SWAP_EYES -e QT_STEREO_OFF \
  -e QT_STEREO_OPENGLWINDOW -e QT_STEREO_TOPLEVEL -e QT_STEREO_CHILD -e QT_STEREO_FINISH -e QT_STEREO_FRAMES -e QT_STEREO_PLAIN \
  -e QT_LOGGING_RULES -e QT_QPA_PLATFORM_OVERRIDE -e MESA_DEBUG -e LIBGL_DEBUG -e EGL_LOG_LEVEL \
  -v "$here/passwd:/etc/passwd:ro" -v "$here:/rig:ro" -v "$ev:/ev" -v "$here/clips:/clips:ro" \
  ${IMG:-qtbase-proof:ours} /rig/run-case.sh "$case_" "$@"
