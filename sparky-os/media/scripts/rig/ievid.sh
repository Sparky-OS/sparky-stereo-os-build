#!/bin/bash
cd /K3D/temp/partners/queue/media-on-dmo/work/rig
for vo in gpu-next gpu; do
  STEPS='[["wait",3.0],["get","interpolation"],["get","video-sync"],["get","display-fps"],["get","tscale"],["get","vo-passes"],["wait",0.3],["get","vo-passes"],["cap"]]' MPVBIN=mpv TAILN=0 GEOM=--geometry=960x540 scripts/run.sh ievid-$vo players-stereo-r3:final $vo clips/i24-sbs.mkv '[1]' --video-sync=display-resample --interpolation --tscale=linear --loop-file=inf --input-ipc-server=/tmp/mpv.sock > /dev/null 2>&1
done
