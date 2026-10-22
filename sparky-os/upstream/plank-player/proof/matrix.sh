#!/bin/bash
# usage: matrix.sh <prefix> <mode: osd|plain> <clips...>: each clip (the looped L- copies) played in Plank Player under headless KWin,
# 6 captures with the on-screen display open (osd: the first 5 seconds) or closed (plain), analysis per capture
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
W=${SPARKY_WORKSPACES:?}/plank-player
p=$1; mode=$2; shift 2
if [ $mode = osd ]; then steps='[["wait",2.2],["cap","c1"],["wait",0.2],["cap","c2"],["wait",0.3],["cap","c3"],["wait",0.2],["cap","c4"],["wait",0.1],["cap","c5"],["wait",0.1],["cap","c6"]]'
else steps='[["wait",7],["cap","c1"],["wait",0.4],["cap","c2"],["wait",0.7],["cap","c3"],["wait",0.5],["cap","c4"],["wait",0.9],["cap","c5"],["wait",0.6],["cap","c6"]]'; fi
for c in "$@"; do
  n=$p-$mode-${c%.*}
  $W/run/rp.sh $n L-$c "$steps" >/dev/null 2>&1
  echo "== $c ($mode): declarations=$(grep -c 'set_content(3)' $W/out/$n/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$n/client0.log)"
  $W/run/ana.sh $n 2>&1 | grep -v dbus | cut -c1-220
done
