#!/bin/bash
# usage: drun.sh [-e VAR=val]... <run-kubrick args>   (GPU by default; SOFT=1 for software GL)
envs=()
if [ -n "${SOFT:-}" ]; then envs+=(-e LIBGL_ALWAYS_SOFTWARE=1 -e EGL_PLATFORM=surfaceless); fi
exec docker run --rm --platform linux/amd64 -u $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE \
  ${GPU:+--device /dev/dri/renderD128 --group-add 125} \
  -e QT_STEREO_WIDTH -e QT_STEREO_HEIGHT -e QT_STEREO_HOLD_MS -e VP_LOG -e STATIC_ONLY -e PLAT -e CLIENT_SOFT -e NOFREEZE -e MYQT -e FREEZE_AT -e FREEZE_SECONDS -e DETERMINISTIC -e NO_FINISH -e LP_NUM_THREADS -e LIBGL_ALWAYS_SOFTWARE -e QT_DEBUG_PLUGINS -e QT_LOGGING_RULES -e QT_WAYLAND_DEBUG -e KUBRICK_DEBUG \
  -v /K3D/temp/partners/queue/kde-science-camera/work/passwd:/etc/passwd:ro -v /K3D/temp/partners/queue/kde-science-camera/work:/o -v /K3D/temp/sparky-os/repo:/repo:ro kdesci-kubrick:1 /o/run-kubrick.sh "$@"
