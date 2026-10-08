#!/bin/sh
# md5 of every decoded video frame (pixels only, no side data) of every clip, one thread count at a time
for th in 1 4; do
  for f in /clips/*; do
    n=$(basename $f)
    s=$(ffmpeg -v error -threads $th -i $f -map 0:v:0 -f framemd5 - 2>/dev/null | grep -v '^#' | md5sum | cut -c1-32)
    c=$(ffmpeg -v error -threads $th -i $f -map 0:v:0 -f framemd5 - 2>/dev/null | grep -vc '^#')
    echo "$th $n $c $s"
  done
done
