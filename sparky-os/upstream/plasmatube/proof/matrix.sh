#!/bin/bash
# usage: matrix.sh <prefix> <ids...>: for each video id play it in PlasmaTube (headless KWin), 6 captures, analysis per capture
W=/K3D/temp/partners/queue/plasmatube
p=$1; shift
for id in "$@"; do
  IMG=${IMG:-pt-run:B} $W/run/rp.sh $p-$id $id '[["wait",12],["fi",760,300],["wait",1],["fi",730,477,"click"],["wait",2],["fi",1000,650],["wait",3],["cap","c1"],["wait",0.4],["cap","c2"],["wait",0.7],["cap","c3"],["wait",0.5],["cap","c4"],["wait",0.9],["cap","c5"],["wait",0.6],["cap","c6"]]' >/dev/null 2>&1
  echo "== $id: declarations=$(grep -c 'set_content(3)' $W/out/$p-$id/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$p-$id/client0.log)"
  IMG=${IMG:-pt-run:B} $W/run/ana.sh $p-$id 2>&1 | grep -v dbus | cut -c1-200
done
