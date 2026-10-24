#!/bin/sh
set -eu
for name in h264-right8 h264-cancel8 mpeg2-eyes8 vp9-eyes8 vp9-eyes10; do
 for mode in software hardware; do
  if [ "$mode" = software ]; then api=software; required=0; else api=$API; required=1; fi
  /w/decode-proof /w/fixtures/$name.mkv "$api" /w/final/$GPU/$name-$mode.raw "$required" > /w/final/$GPU/$name-$mode.csv 2>/w/final/$GPU/$name-$mode.err
 done
done
