#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/kde-science-camera/work
export PLAT=xcb GPU=1 FREEZE_SECONDS=14 FREEZE_AT=${FA:-150}
run() { n=$1; fl=$2; shift 2; ./drun.sh $n $fl 1280x800 -- "$@" > /dev/null 2>&1; echo done $n; }
unset CLIENT_SOFT
run gpu-s5-1 patched --stereo
run gpu-s5-2 patched --stereo
run gpu-s10-1 patched --stereo --stereo-separation 10
run gpu-off-1 patched
run gpu-off-debian-1 debian
export CLIENT_SOFT=1
run sw-s5-1 patched --stereo
run sw-s5-2 patched --stereo
run sw-s5-3 patched --stereo
run sw-s10-1 patched --stereo --stereo-separation 10
run sw-s0-1 patched --stereo --stereo-separation 1
run sw-off-1 patched
run sw-off-debian-1 debian
