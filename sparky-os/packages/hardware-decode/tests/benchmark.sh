#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-bench
for mode in no auto; do
 /usr/bin/time -f 'wall=%e user=%U sys=%S cpu=%P' -o /w/final/$GPU-bench/cpu-$mode.txt /w/mpv-build/mpv --no-config --vo=null --ao=null --hwdec=$mode --loop-file=4 /w/fixtures/h264-sbs8.mp4 > /w/final/$GPU-bench/$mode.log 2>&1
done
