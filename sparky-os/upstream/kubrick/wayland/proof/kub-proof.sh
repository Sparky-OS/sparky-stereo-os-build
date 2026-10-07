#!/bin/bash
# Kubrick proof on the installed packages: native Wayland, headless KWin; usage: kub-proof.sh <prefix>
cd /K3D/temp/kdesci-wl
p=${1:-kp}
export IMG=${IMG:-kdesci-wl:2} FREEZE_AT=60 FREEZE_SECONDS=14 WAIT=5
SHK=/w/tests/kubrick-shim.so
FT=/usr/lib/x86_64-linux-gnu/faketime/libfaketime.so.1
run() { n=$1; shift; env NAME=$p-$n "$@" ./drun.sh >/dev/null 2>&1; echo done $n; }
export STATIC_ONLY=1
for i in 1 2 3; do run sw-s5-$i SOFT=1 SHIM=$SHK CMD="/usr/games/kubrick --stereo"; done
run sw-s10 SOFT=1 SHIM=$SHK CMD="/usr/games/kubrick --stereo --stereo-separation 10"
run sw-s2 SOFT=1 SHIM=$SHK CMD="/usr/games/kubrick --stereo --stereo-separation 2"
for i in 1 2; do run gpu-s5-$i SHIM=$SHK CMD="/usr/games/kubrick --stereo"; done
run xcb-sw-s5 PLAT=xcb SOFT=1 SHIM=$SHK CMD="/usr/games/kubrick --stereo"
run xcb-gpu-s5 PLAT=xcb SHIM=$SHK CMD="/usr/games/kubrick --stereo"
unset STATIC_ONLY
export DETERMINISTIC=1 FAKETIME="2026-10-07 12:00:00"
for i in 1 2; do run off-$i SHIM=$FT:$SHK CMD="/usr/games/kubrick"; run offdeb-$i SHIM=$FT:$SHK LD_LIBRARY_PATH=/deb/x/usr/lib/x86_64-linux-gnu XDG_DATA_DIRS=/deb/x/usr/share:/usr/share CMD="/deb/x/usr/games/kubrick"; done
run gpuoff-1 SHIM=$FT:$SHK CMD="/usr/games/kubrick"
run gpuoffdeb-1 SHIM=$FT:$SHK LD_LIBRARY_PATH=/deb/x/usr/lib/x86_64-linux-gnu XDG_DATA_DIRS=/deb/x/usr/share:/usr/share CMD="/deb/x/usr/games/kubrick"
run xcb-off-1 PLAT=xcb SHIM=$FT:$SHK CMD="/usr/games/kubrick"
run xcb-offdeb-1 PLAT=xcb SHIM=$FT:$SHK LD_LIBRARY_PATH=/deb/x/usr/lib/x86_64-linux-gnu XDG_DATA_DIRS=/deb/x/usr/share:/usr/share CMD="/deb/x/usr/games/kubrick"
echo ALLDONE
