#!/bin/sh
# SAR that FFmpeg reads from each file, and the pasp the MP4 muxer writes for it
cd /out/sar
ffmpeg -version | head -1
printf "%-24s %-10s %-12s %-10s\n" file SAR DAR "mp4 pasp"
for f in *.mkv; do
  b=$(basename $f .mkv)
  line=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,sample_aspect_ratio,display_aspect_ratio -of csv=p=0 $f)
  ffmpeg -v error -y -i $f -c copy -strict unofficial /out/sar/$b.mp4
  printf "%-24s %s\n" $b "$line"
done
