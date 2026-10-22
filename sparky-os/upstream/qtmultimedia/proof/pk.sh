#!/bin/bash
# Plank Player (dev build) proofs. usage: [DEV=1] pk.sh plain|osd|manual <prefix> ...
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
W=${SPARKY_SCRATCH:?}/qtmm-lane
export APPCMD=${PLANKBIN:-/w/plank-prefix/bin/plank-player} NO_BAR=1
mode=$1; p=$2; shift 2
case $mode in
plain)
  for c in "$@"; do
    n=$p-plain-${c%.*}
    $W/run/rt.sh $n '[["wait",7],["cap","c1"],["wait",0.4],["cap","c2"],["wait",0.7],["cap","c3"],["wait",0.5],["cap","c4"],["wait",0.9],["cap","c5"],["wait",0.6],["cap","c6"]]' /w/clips/L-$c >/dev/null 2>&1
    echo "== $n: declarations=$(grep -c 'set_content(3)' $W/out/$n/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$n/client0.log)"
    $W/run/ana2.sh $n 2>&1 | grep -v dbus
  done;;
osd)
  for c in "$@"; do
    n=$p-osd-${c%.*}
    $W/run/rt.sh $n '[["wait",2.2],["cap","c1"],["wait",0.2],["cap","c2"],["wait",0.3],["cap","c3"],["wait",0.2],["cap","c4"],["wait",0.1],["cap","c5"],["wait",0.1],["cap","c6"]]' /w/clips/L-$c >/dev/null 2>&1
    echo "== $n: declarations=$(grep -c 'set_content(3)' $W/out/$n/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$n/client0.log)"
    $W/run/ana2.sh $n 2>&1 | grep -v dbus
    docker run --rm --platform linux/amd64 -v $W:/w qtmm-run:3 sh -c "python3 /w/run/osdcheck.py /w/out/$n/c*.png" | cut -c1-200
  done;;
manual)
  # usage: manual <prefix> <name> <clip> <downs...>
  name=$1; clip=$2; shift 2
  steps='[["wait",2],["fk",106,7,350],["fk",28,1],["wait",0.8]'
  for n in "$@"; do steps="$steps"',["fk",108,'$n',350],["fk",28,1],["wait",0.8]'; done
  steps="$steps"',["cap","m1"],["fk",1,1],["wait",6.5],["cap","c1"],["wait",0.4],["cap","c2"],["wait",0.7],["cap","c3"],["wait",0.5],["cap","c4"]]'
  n=$p-man-$name
  $W/run/rt.sh $n "$steps" /w/clips/$clip >/dev/null 2>&1
  echo "== $name: declarations=$(grep -c 'set_content(3)' $W/out/$n/client0.log) subsurfaces=$(grep -c get_subsurface $W/out/$n/client0.log)"
  $W/run/ana2.sh $n 2>&1 | grep -v dbus;;
esac
