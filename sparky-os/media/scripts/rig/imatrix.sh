#!/bin/bash
# usage: imatrix.sh <prefix> <image> <mpvbin|mpv> -> results-<prefix>.txt   (both outputs x tscale default/linear x cases)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
pre=$1; img=$2; export MPVBIN=${3:-mpv}; : > results-$pre.txt
C=/w/clips
for vo in gpu-next gpu; do for ts in default linear; do
  tsa=""; [ $ts = linear ] && tsa="--tscale=linear"
  for case in steady seek pause change layout; do
    nm=$pre-$vo-$ts-$case
    case $case in
      steady|seek|pause) clip=i24-sbs.mkv; extra=""; exp=3d;;
      change) clip=i24-sbs.mkv; extra="$C/i24-sbs.mkv $C/i24-2d.mkv"; exp=change;;
      layout) clip=i24-sbs.mkv; extra="$C/i24-sbs.mkv"; exp=3d;;
    esac
    [ $case = layout ] && { clip=i24-tb.mkv; }
    [ $case = layout ] && extra="$C/i24-sbs.mkv"
    STEPS=$(python3 scripts/isteps.py $case) TAILN=0 GEOM=--geometry=960x540 scripts/run.sh $nm $img $vo clips/$clip '[1]' --video-sync=display-resample --interpolation --loop-file=inf --input-ipc-server=/tmp/mpv.sock $tsa $extra > /dev/null 2>&1
    python3 scripts/interp.py runs/$nm > runs/$nm/interp.txt 2>&1
    python3 scripts/ijudge.py runs/$nm $exp | sed "s/^\(PASS\|FAIL\) /\1 [$ts] /" >> results-$pre.txt
  done
done; done
