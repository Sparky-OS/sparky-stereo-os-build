#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
for vo in gpu-next gpu; do for ts in default linear; do
  tsa=""; [ $ts = linear ] && tsa="--tscale=linear"
  for b in old new; do
    mb=mpv; [ $b = new ] && mb=/mpvb2/mpv
    nm=i2d-$b-$vo-$ts
    STEPS='[["wait",3.0],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["wait",0.15],["cap"],["get","vo-passes"],["ipc",["set_property","pause",true]],["wait",0.3],["ipc",["seek",2.0,"absolute+exact"]],["wait",1.0],["cap"]]' MPVBIN=$mb TAILN=0 GEOM=--geometry=960x540 scripts/run.sh $nm players-stereo-r2:final $vo clips/i24-2d.mkv '[1]' --video-sync=display-resample --interpolation --loop-file=inf --input-ipc-server=/tmp/mpv.sock $tsa > /dev/null 2>&1
    python3 scripts/interp.py runs/$nm > runs/$nm/interp.txt 2>&1
  done
done; done
