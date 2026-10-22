#!/bin/bash
# usage: analyze-all.sh <prefix>   writes analysis.txt and surfaces.txt into every ev/<prefix>-* case and prints a one-line summary
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtgl/ev
for d in $1-*; do
  [ -f $d/app.raw ] || continue
  python3 ../rig/wlsurf.py $d/app.raw > $d/surfaces.txt 2>&1
  case $d in
    *-kub-sw*|*-kub-gpu*) python3 ../rig/an-kub.py $d 5 > $d/analysis.txt 2>&1 ;;
    *-ka-sw*|*-ka-gpu*) python3 ../rig/an-ka.py $d 5 > $d/analysis.txt 2>&1 ;;
    *-kz-*sw|*-kz-*gpu) python3 ../rig/an-kz.py $d ../rig/chain.xyz > $d/analysis.txt 2>&1 ;;
  esac
  echo "$d: $(head -2 $d/capture.txt | tr '\n' ' ') | $(grep -E 'declared' $d/surfaces.txt)"
done
