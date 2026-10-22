#!/bin/bash
# usage: proof-all.sh <image> <old-image> <evidence-dir>
# image: Krita +stereo3d4 installed from the repository; old-image: Krita +stereo3d1 (Part 1) for the stereo-off comparisons.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
img=$1; old=$2; ev=$3; mkdir -p $ev
here=$(cd "$(dirname "$0")" && pwd)
run() { local n=$1; shift; rm -rf ${SPARKY_SCRATCH:?}/krita-p3b/ev/$n; IMG=${RIMG:-$img} $here/kdrun.sh $n "$@" > ${SPARKY_SCRATCH:?}/krita-p3b/ev/$n.drun.log 2>&1; }
STEREO="KRC=stereo3DCanvas=true"
# 1. a side-by-side pair, GPU, no shim, WAYLAND_DEBUG for the declarations
run s-pair -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=60 -e KENV=WAYLAND_DEBUG=1
run s-palette -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=60 -e "INPUT=move 320 400 sleep 500 rclick sleep 1500"
# 2. the 16-bit ramp: a stereo document, and a normal document in the same kind of session (Stereo 3D on at start)
run s-ramp -e FILE=/k/t/ramp-sbs.png -e "$STEREO" -e WAIT=60 -e SHIM=1
run m-ramp -e FILE=/k/t/ramp-mono.png -e "$STEREO" -e WAIT=60 -e SHIM=1
# 3. stereo off: the normal ramp document, and the pair, new package against the Part 1 package
run off-ramp -e FILE=/k/t/ramp-mono.png -e WAIT=60 -e SHIM=1
run off-new -e FILE=/k/t/pair-sbs.png -e WAIT=60
RIMG=$old run off-ramp-old -e FILE=/k/t/ramp-mono.png -e WAIT=60 -e SHIM=1
RIMG=$old run off-old -e FILE=/k/t/pair-sbs.png -e WAIT=60
# 4. two documents, a normal one and a pair: the tab of the normal one is clicked (the window is at 211,117 on the screen)
run s-switch -e KARGS=/k/t/ramp-mono.png -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=80 -e "INPUT=move 401 217 sleep 300 click sleep 3000"
# 5. Qt's xcb platform, stereo on, software GL (as Part 2)
run s-xcb -e FILE=/k/t/pair-sbs.png -e "$STEREO" -e WAIT=60 -e XCB=1 -e KENV=LIBGL_ALWAYS_SOFTWARE=1
for n in s-pair s-palette s-ramp m-ramp off-ramp off-new off-ramp-old off-old s-switch s-xcb; do rm -rf $ev/$n; cp -r ${SPARKY_SCRATCH:?}/krita-p3b/ev/$n $ev/$n; done
