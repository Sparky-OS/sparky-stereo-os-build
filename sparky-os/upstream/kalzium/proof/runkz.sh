#!/bin/bash
cd /K3D/temp/partners/queue/kde-science-camera/work
export IMG=kdesci-kalz:2 GEOM_EVERY=1 START_WAIT=14 GPU=1
unset INPUT
MOL=/o/tests/chain.xyz
run() { n=$1; xd=$2; shift 2; ./drun-app.sh $n $xd usr/bin/kalzium 1280x800 -- "$@" > /dev/null 2>&1; echo done $n; }
PATCHED="SHIM=/o/tests/gl-shim.so:/o/tests/avogadro-aid3.so APPLD=/o/x-kalzium/usr/lib/x86_64-linux-gnu"
DEBIAN="SHIM=/o/tests/gl-shim.so:/o/tests/avogadro-aid3-debian.so APPLD=/o/x-kalzium-debian/usr/lib/x86_64-linux-gnu"
export CLIENT_SOFT=1
env $PATCHED bash -c "$(declare -f run); run kz-sw-s5 x-kalzium --stereo -m $MOL"
env $PATCHED bash -c "$(declare -f run); run kz-sw-s5b x-kalzium --stereo -m $MOL"
env $PATCHED bash -c "$(declare -f run); run kz-sw-off x-kalzium -m $MOL"
env $DEBIAN bash -c "$(declare -f run); run kz-sw-off-debian x-kalzium-debian -m $MOL"
unset CLIENT_SOFT
env $PATCHED bash -c "$(declare -f run); run kz-gpu-s5 x-kalzium --stereo -m $MOL"
env $PATCHED bash -c "$(declare -f run); run kz-gpu-off x-kalzium -m $MOL"
env $DEBIAN bash -c "$(declare -f run); run kz-gpu-off-debian x-kalzium-debian -m $MOL"
