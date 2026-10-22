#!/bin/bash
# usage: [PLAT=xcb|wayland] [ACT=script] [SIZE=1280x800] [WAIT=seconds] drun.sh <case> -- <bino args...>
# Runs the case inside the bino-stereo-proof container (debian:testing + our dev repo + deb-multimedia Bino).
# Work dir ${SPARKY_SCRATCH}/bino-lane/o is /o inside; clips ${SPARKY_SCRATCH}/bino-lane/clips is /clips; evidence goes to <this dir>/../evidence/<case>.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
here=$(cd "$(dirname "$0")" && pwd)
case_=$1; shift; [ "$1" = "--" ] && shift
mkdir -p "$here/../evidence/$case_"
exec docker run --rm --platform linux/amd64 -u $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE \
  --device /dev/dri/renderD128 --group-add 125 \
  -e PLAT -e ACT -e SIZE -e WAIT -e LIBGL_ALWAYS_SOFTWARE -e BINO_BIN -e BINO_ENV -e BINO_LOG -e DX -e DY -e KEEP_CFG \
  -v ${SPARKY_SCRATCH:?}/bino-lane/passwd:/etc/passwd:ro \
  -v ${SPARKY_SCRATCH:?}/bino-lane/o:/o -v ${SPARKY_SCRATCH:?}/bino-lane/clips:/clips:ro \
  -v "$here":/proof:ro -v "$here/../evidence/$case_":/ev \
  ${IMG:-bino-stereo-proof:4} /proof/run-bino.sh "$case_" "$@"
