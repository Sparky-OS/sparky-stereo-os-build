#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/kdesci-wl
p=${1:-ka}
export IMG=${IMG:-kdesci-wl:1} WAIT=14 SHIM=/w/tests/gl-shim.so GEOM_EVERY=1
unset FREEZE_AT FREEZE_SECONDS STATIC_ONLY DETERMINISTIC FAKETIME
export INPUT="move 600 400 sleep 300 click sleep 500 keydown 0xffe9 keydown 0x33 keyup 0x33 keyup 0xffe9 sleep 2500"
DEB="LD_LIBRARY_PATH=/deb/x/usr/lib/x86_64-linux-gnu XDG_DATA_DIRS=/deb/x/usr/share:/usr/share"
run() { n=$1; shift; env NAME=$p-$n "$@" ./drun.sh >/dev/null 2>&1; echo done $n; }
run sw-s5 SOFT=1 CMD="/usr/bin/kalgebra --stereo"
run gpu-s5 CMD="/usr/bin/kalgebra --stereo"
run sw-s10 SOFT=1 CMD="/usr/bin/kalgebra --stereo --stereo-separation 10"
run sw-s2 SOFT=1 CMD="/usr/bin/kalgebra --stereo --stereo-separation 2"
run xcb-sw-s5 PLAT=xcb SOFT=1 CMD="/usr/bin/kalgebra --stereo"
run xcb-gpu-s5 PLAT=xcb CMD="/usr/bin/kalgebra --stereo"
run sw-off SOFT=1 CMD="/usr/bin/kalgebra"
run sw-offdeb SOFT=1 $DEB CMD="/deb/x/usr/bin/kalgebra"
run gpu-off CMD="/usr/bin/kalgebra"
run gpu-offdeb $DEB CMD="/deb/x/usr/bin/kalgebra"
run xcb-off PLAT=xcb SOFT=1 CMD="/usr/bin/kalgebra"
run xcb-offdeb PLAT=xcb SOFT=1 $DEB CMD="/deb/x/usr/bin/kalgebra"
echo ALLDONE
