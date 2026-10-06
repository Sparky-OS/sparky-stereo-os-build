#!/bin/bash
cd /K3D/temp/partners/queue/kde-science-camera/work
export INPUT=/o/input-3d.sh IMG=kdesci-kalg:3 GEOM_EVERY=1 START_WAIT=14 GPU=1
run() { n=$1; xd=$2; shift 2; ./drun-app.sh $n $xd usr/bin/kalgebra 1280x800 -- "$@" > /dev/null 2>&1; echo done $n; }
export CLIENT_SOFT=1
run ka-sw-s5 x-kalgebra --stereo
run ka-sw-s10 x-kalgebra --stereo --stereo-separation 10
unset CLIENT_SOFT
run ka-gpu-s5 x-kalgebra --stereo
