#!/bin/bash
# usage: manual.sh <prefix> <name> <clip> <downs...>: a video that declares nothing, the input format chosen with the remote control keys only
# (KWin fake input): Right x7 to the 3D button of the on-screen display, Return opens the menu (focus on its first entry), then for each number
# n: Down x n, Return (entry 5 = Side by Side Half, 6 = Full, 7 = Top and Bottom Half, 8 = Full, 15 = Not 3D, 16 = Swap Eyes; the list
# starts at 3D = 0, the focus keeps its place, so n is the distance from the previous choice); Escape closes the menu; 6 captures after the
# on-screen display has gone, the capture m1 with the menu open
W=/K3D/temp/partners/queue/plank-player
p=$1; name=$2; clip=$3; shift 3
steps='[["wait",2],["fk",106,7,350],["fk",28,1],["wait",0.8]'
for n in "$@"; do steps="$steps"',["fk",108,'$n',350],["fk",28,1],["wait",0.8]'; done
steps="$steps"',["cap","m1"],["fk",1,1],["wait",6.5],["cap","c1"],["wait",0.4],["cap","c2"],["wait",0.7],["cap","c3"],["wait",0.5],["cap","c4"],["wait",0.9],["cap","c5"],["wait",0.6],["cap","c6"]]'
n=$p-man-$name
$W/run/rp.sh $n $clip "$steps" >/dev/null 2>&1
echo "== $name: declarations=$(grep -c 'set_content(3)' $W/out/$n/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$n/client0.log)"
$W/run/ana.sh $n 2>&1 | grep -v dbus | cut -c1-220
