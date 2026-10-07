#!/bin/bash
# usage: [DEV=1] [APPCMD=...] [CROP_TOP=n NO_BAR=1] mx.sh <prefix> "<clip> [app args...]" ... : each entry plays one clip (3 captures), then declarations/subsurfaces and the analysis
W=/K3D/temp/qtmm-lane
p=$1; shift
for e in "$@"; do
  set -- $e; c=$1; shift
  n=$p-${c%.*}$( [ $# -gt 0 ] && echo "-$(echo $* | tr ' ' '_')" )
  $W/run/rt.sh $n "${STEPS:-[[\"wait\",${WAIT:-6}],[\"cap\",\"c1\"],[\"wait\",0.4],[\"cap\",\"c2\"],[\"wait\",0.7],[\"cap\",\"c3\"]]}" /w/clips/$c "$@" >/dev/null 2>&1
  echo "== $n: declarations=$(grep -c 'set_content(3)' $W/out/$n/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$n/client0.log) buffers=$(grep -o 'create_buffer(new id wl_buffer#[0-9]*, 0, [0-9]*, [0-9]*, [0-9]*, [0-9]*)' $W/out/$n/client0.log | sed 's/.*0, //' | sort | uniq -c | tr '\n' ';')"
  $W/run/ana2.sh $n 2>&1 | grep -v dbus
done
