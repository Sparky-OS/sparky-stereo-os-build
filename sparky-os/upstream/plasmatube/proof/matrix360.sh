#!/bin/bash
# usage: matrix360.sh <prefix>: every 360/VR180 clip played in PlasmaTube, three captures (straight ahead, then the view dragged on twice)
W=/K3D/temp/partners/queue/plasmatube
p=$1
while read id kind clip dx; do
  $W/run/pan.sh $p-$id $id $dx
  echo "== $id ($clip): declarations=$(grep -c 'set_content(3)' $W/out/$p-$id/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$p-$id/client0.log)"
  $W/run/ana360.sh $kind $clip $p-$id 2>&1 | grep -v dbus
done <<LIST
p-tb-sm 360 s360-tb-sm.mp4 289
p-tb-mkv 360 s360-tb.mkv 289
p-tb-plain 360 s360-tb.mp4 289
p-tb-plain-nohint 360 s360-tb.mp4 289
p-mono-sm 360 mono360-sm.mp4 289
p-mono-mkv 360 mono360.mkv 289
p-mono-plain 360 mono360.mp4 289
p-vr180-sm 180 vr180-sbs-sm.mp4 260
p-vr180-plain 180 vr180-sbs.mp4 260
LIST
