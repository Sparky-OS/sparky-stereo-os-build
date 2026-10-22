#!/bin/bash
# usage: proof-all.sh <image> <old-image> <evidence-dir>
# image: Krita +stereo3d3 installed from the repository; old-image: Krita +stereo3d1 (Part 1) for the stereo-off comparison.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
img=$1; old=$2; ev=$3; mkdir -p $ev
here=$(cd "$(dirname "$0")" && pwd)
run() { # name, extra docker -e args...
  local n=$1; shift
  rm -rf ${SPARKY_SCRATCH:?}/krita-p3/ev/$n; IMG=$img $here/kdrun.sh $n "$@" > ${SPARKY_SCRATCH:?}/krita-p3/ev/$n.drun.log 2>&1
}
STEREO="KRC=stereo3DCanvas=true"
# 1. a side-by-side pair, GPU, no shim, WAYLAND_DEBUG for the declarations
run s-pair -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=60 -e KENV=WAYLAND_DEBUG=1
# 1b. the same, Krita's popup palette (right click) open over the stereo canvas: a 2D overlay over the 3D area
run s-palette -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=60 -e "INPUT=move 320 400 sleep 500 rclick sleep 1500"
# 2. the 16-bit ramp, GPU, readback shim
run s-ramp -e FILE=/k/t/ramp-sbs.png -e "$STEREO" -e WAIT=60 -e SHIM=1
# 3. stereo off, the same document, new package and Part 1 package
run off-new -e FILE=/k/t/pair-sbs.png -e WAIT=60
rm -rf ${SPARKY_SCRATCH:?}/krita-p3/ev/off-old; IMG=$old $here/kdrun.sh off-old -e FILE=/k/t/pair-sbs.png -e WAIT=60 > ${SPARKY_SCRATCH:?}/krita-p3/ev/off-old.drun.log 2>&1
# 4. stereo on, Qt's xcb platform, software GL (as Part 2)
run s-xcb -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=60 -e XCB=1 -e KENV=LIBGL_ALWAYS_SOFTWARE=1
for n in s-pair s-palette s-ramp off-new off-old s-xcb; do rm -rf $ev/$n; cp -r ${SPARKY_SCRATCH:?}/krita-p3/ev/$n $ev/$n; done
