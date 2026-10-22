#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/kdesci-wl
p=${1:-kz}
export IMG=${IMG:-kdesci-wl:1} WAIT=16 GEOM_EVERY=1
unset FREEZE_AT FREEZE_SECONDS STATIC_ONLY DETERMINISTIC FAKETIME INPUT
S=/w/tests/gl-shim.so
DEB="LD_LIBRARY_PATH=/deb/x/usr/lib/x86_64-linux-gnu XDG_DATA_DIRS=/deb/x/usr/share:/usr/share"
MOL=/w/tests/chain.xyz
run() { n=$1; shift; env NAME=$p-$n "$@" ./drun.sh >/dev/null 2>&1; echo done $n; }
run sw-s5 SOFT=1 SHIM=$S CMD="/usr/bin/kalzium --stereo -m $MOL"
run sw-s5b SOFT=1 SHIM=$S CMD="/usr/bin/kalzium --stereo -m $MOL"
run gpu-s5 SHIM=$S CMD="/usr/bin/kalzium --stereo -m $MOL"
run xcb-sw-s5 PLAT=xcb SOFT=1 SHIM=$S CMD="/usr/bin/kalzium --stereo -m $MOL"
run xcb-gpu-s5 PLAT=xcb SHIM=$S CMD="/usr/bin/kalzium --stereo -m $MOL"
run sw-off SOFT=1 SHIM=$S CMD="/usr/bin/kalzium -m $MOL"
run sw-offdeb SOFT=1 SHIM=$S:/w/tests/avogadro-aid3-debian.so $DEB CMD="/deb/x/usr/bin/kalzium -m $MOL"
run sw-black SOFT=1 SHIM=$S $DEB CMD="/deb/x/usr/bin/kalzium -m $MOL"
run gpu-off SHIM=$S CMD="/usr/bin/kalzium -m $MOL"
run gpu-offdeb SHIM=$S:/w/tests/avogadro-aid3-debian.so $DEB CMD="/deb/x/usr/bin/kalzium -m $MOL"
run xcb-off PLAT=xcb SOFT=1 SHIM=$S CMD="/usr/bin/kalzium -m $MOL"
run xcb-offdeb PLAT=xcb SOFT=1 SHIM=$S:/w/tests/avogadro-aid3-debian.so $DEB CMD="/deb/x/usr/bin/kalzium -m $MOL"
echo ALLDONE
