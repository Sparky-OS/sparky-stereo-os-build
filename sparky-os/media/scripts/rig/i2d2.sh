#!/bin/bash
# 2D paused still after an exact seek, repeated, old build (mpv in the image) and new (/mpvb2/mpv), with and without --dither=no
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
for vo in gpu-next gpu; do for dv in dither dithno; do for b in old new; do for rep in 1 2; do
  mb=mpv; [ $b = new ] && mb=/mpvb2/mpv; da=""; [ $dv = dithno ] && da="--dither=no"
  nm=j2d-$vo-$dv-$b-$rep
  STEPS='[["wait",3.0],["ipc",["set_property","pause",true]],["wait",0.3],["ipc",["seek",2.0,"absolute+exact"]],["wait",1.0],["cap"]]' MPVBIN=$mb TAILN=0 GEOM=--geometry=960x540 scripts/run.sh $nm players-stereo-r2:final $vo clips/i24-2d.mkv '[1]' --video-sync=display-resample --interpolation --tscale=linear --loop-file=inf --vd-lavc-threads=1 --input-ipc-server=/tmp/mpv.sock $da > /dev/null 2>&1
done; done; done; done
