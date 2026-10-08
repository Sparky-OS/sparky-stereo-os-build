#!/bin/bash
# usage: irun.sh <name> <image> <vo> <clip> [mpv args...]  env: MPVBIN, TIMES (json), STEPS; interpolation on 60 Hz output
cd /K3D/temp/partners/queue/media-on-dmo/work/rig
export TAILN=0 GEOM=${GEOM:---geometry=960x540}
MPVBIN=${MPVBIN:-mpv} scripts/run.sh $1 $2 $3 clips/$4 "${TIMES:-[3,3.15,3.3,3.45,3.6,3.75,3.9,4.05,4.2,4.35,4.5,4.65,4.8,4.95,5.1,5.25]}" --video-sync=display-resample --interpolation --loop-file=inf "${@:5}" > /dev/null 2>&1
python3 scripts/interp.py runs/$1 > runs/$1/interp.txt 2>&1
