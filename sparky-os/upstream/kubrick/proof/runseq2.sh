#!/bin/bash
cd /K3D/temp/partners/queue/kde-science-camera/work
export PLAT=xcb GPU=1 FREEZE_SECONDS=14 FREEZE_AT=${FA:-60} STATIC_ONLY=1
run() { n=$1; fl=$2; shift 2; ./drun.sh $n $fl 1280x800 -- "$@" > /dev/null 2>&1; echo done $n; }
export CLIENT_SOFT=1
for i in 1 2 3; do run st-sw-s5-$i patched --stereo; done
run st-sw-s10-1 patched --stereo --stereo-separation 10
run st-sw-s2-1 patched --stereo --stereo-separation 2
unset CLIENT_SOFT
for i in 1 2; do run st-gpu-s5-$i patched --stereo; done
