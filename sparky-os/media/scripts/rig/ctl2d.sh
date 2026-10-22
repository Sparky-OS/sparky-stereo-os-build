#!/bin/bash
# The 2D control (round 3's j2d procedure): a 2D clip, paused first, then an exact seek, one capture, with
# interpolation and a linear tscale and one decoder thread, so that the frame on the screen is the same every run.
# usage: ctl2d.sh <prefix> <image-dmo> <image-ours> [reps]   -> runs/<prefix>-<vo>-<dither>-<dmo|ours>-<rep>, then ctl2d_cmp.py
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
pre=$1; imgd=$2; imgo=$3; reps=${4:-2}
for vo in gpu-next gpu; do for dv in dither dithno; do for b in dmo ours; do for rep in $(seq $reps); do
  img=$imgd; [ $b = ours ] && img=$imgo; da=""; [ $dv = dithno ] && da="--dither=no"
  nm=$pre-$vo-$dv-$b-$rep
  STEPS='[["wait",3.0],["ipc",["set_property","pause",true]],["wait",0.3],["ipc",["seek",2.0,"absolute+exact"]],["wait",1.0],["cap"]]' TAILN=0 GEOM=--geometry=960x540 scripts/run.sh $nm $img $vo clips/${CLIP:-i24-2d.mkv} '[1]' --video-sync=display-resample --interpolation --tscale=linear --loop-file=inf --vd-lavc-threads=1 --input-ipc-server=/tmp/mpv.sock $da > /dev/null 2>&1
done; done; done; done
python3 scripts/ctl2d_cmp.py $pre
