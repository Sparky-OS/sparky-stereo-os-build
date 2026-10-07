#!/bin/bash
cd "$(dirname "$0")"; export BINO_ENV="LD_PRELOAD=/o/finish-shim.so" WAIT=10
run() { n=$1; shift; ./drun.sh g-$n -- --stereo -o stereo -l one "$@" >/dev/null 2>&1; echo "$n: $(grep -h -E 'meta data from ffprobe|input mode for' ../evidence/g-$n/bino.log | sed 's/Bino: //' | tr '\n' ';')"; }
run sei-halfL /clips/sei-halfsbs-L.mp4
run told-halfL -i left-right-half /clips/sei-halfsbs-L.mp4
python3 analyze.py ../evidence/g-sei-halfL ../evidence/g-told-halfL
