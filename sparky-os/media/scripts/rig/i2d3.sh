#!/bin/bash
cd /K3D/temp/partners/queue/media-on-dmo/work/rig
for vo in gpu-next gpu; do for b in old1 old2 new1 new2; do
  mb=mpv; case $b in new*) mb=/mpvb2/mpv;; esac
  nm=k2d-$vo-$b
  STEPS='[["wait",3.0],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["ipc",["set_property","pause",true]],["wait",0.3],["ipc",["seek",2.0,"absolute+exact"]],["wait",1.0],["cap"]]' MPVBIN=$mb TAILN=0 GEOM=--geometry=960x540 scripts/run.sh $nm players-stereo-r2:final $vo clips/i24-2d.mkv '[1]' --video-sync=display-resample --interpolation --tscale=linear --loop-file=inf --input-ipc-server=/tmp/mpv.sock > /dev/null 2>&1
done; done
