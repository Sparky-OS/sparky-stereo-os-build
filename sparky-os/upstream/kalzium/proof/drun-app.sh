#!/bin/bash
# usage: drun.sh [-e VAR=val]... <run-kubrick args>   (GPU by default; SOFT=1 for software GL)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
envs=()
if [ -n "${SOFT:-}" ]; then envs+=(-e LIBGL_ALWAYS_SOFTWARE=1 -e EGL_PLATFORM=surfaceless); fi
exec docker run --rm --platform linux/amd64 -u $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE \
  ${GPU:+--device /dev/dri/renderD128 --group-add 125} \
  -e QT_STEREO_WIDTH -e QT_STEREO_HEIGHT -e QT_STEREO_HOLD_MS -e VP_LOG -e STATIC_ONLY -e PLAT -e CLIENT_SOFT -e APPLD -e GEOM_EVERY -e CAP_CURSOR -e INPUT -e START_WAIT -e SETTLE -e SHIM -e NOFREEZE -e MYQT -e FREEZE_AT -e FREEZE_SECONDS -e DETERMINISTIC -e NO_FINISH -e LP_NUM_THREADS -e LIBGL_ALWAYS_SOFTWARE -e QT_DEBUG_PLUGINS -e QT_LOGGING_RULES -e QT_WAYLAND_DEBUG -e KUBRICK_DEBUG -e MESA_DEBUG -e MESA_GLSL -e MESA_GL_VERSION_OVERRIDE -e MESA_GLSL_VERSION_OVERRIDE -e LIBGL_DEBUG -e QSG_INFO \
  -v ${SPARKY_WORKSPACES:?}/kde-science-camera/work/passwd:/etc/passwd:ro -v ${SPARKY_WORKSPACES:?}/kde-science-camera/work:/o -v ${SPARKY_REPO_DIR:?}:/repo:ro ${IMG:-kdesci-kalg:2} /o/run-app.sh "$@"
