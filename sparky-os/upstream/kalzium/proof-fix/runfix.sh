#!/bin/bash
# Kalzium molecule viewer, without the avogadro-aid: Debian's build, Debian's build + the fix, the stereo build + the fix.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/kalz-fix/o
export IMG=kdesci-kalz:2 GEOM_EVERY=1 START_WAIT=14 GPU=1
unset INPUT
MOL=/o/tests/chain.xyz
run() { n=$1; xd=$2; shift 2; ./drun-app-fix.sh $n $xd usr/bin/kalzium 1280x800 -- "$@" > /dev/null 2>&1; echo done $n; }
SH=/o/tests/gl-shim.so
ENVF="APPLD=/o/x-kalzium/usr/lib/x86_64-linux-gnu"; ENVD="APPLD=/o/x-kalzium-debian/usr/lib/x86_64-linux-gnu"; ENVX="APPLD=/o/x-kalzium-debfix/usr/lib/x86_64-linux-gnu"
for mode in sw gpu; do
  if [ $mode = sw ]; then export CLIENT_SOFT=1; else unset CLIENT_SOFT; fi
  env SHIM=$SH $ENVD bash -c "$(declare -f run); run fx-$mode-debian x-kalzium-debian -m $MOL"
  env SHIM=$SH $ENVX bash -c "$(declare -f run); run fx-$mode-debfix x-kalzium-debfix -m $MOL"
  env SHIM=$SH $ENVF bash -c "$(declare -f run); run fx-$mode-off x-kalzium -m $MOL"
  env SHIM=$SH $ENVF bash -c "$(declare -f run); run fx-$mode-s5 x-kalzium --stereo -m $MOL"
done
export CLIENT_SOFT=1 INPUT=/o/input-kz-drag.sh
env SHIM=$SH $ENVF bash -c "$(declare -f run); run fx-sw-s5-drag x-kalzium --stereo -m $MOL"
