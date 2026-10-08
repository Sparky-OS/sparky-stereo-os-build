#!/bin/sh
# In the container: the fixtures' reading by FFmpeg and the remux to MP4 (default strictness and -strict unofficial); outputs into /out/$1
O=/out/$1; mkdir -p $O
ffmpeg -version | head -1 > $O/version.txt
for f in /fx/h264-mkv-sm*.mkv /fx/h264-sei-sbs-lr.mkv /fx/h264-plain-sbs-lr.mkv "$@"; do
  [ -f "$f" ] || continue
  b=$(basename $f .mkv)
  ffprobe -hide_banner $f > $O/$b.mkv.probe 2>&1
  ffmpeg -v error -y -i $f -c copy -strict unofficial $O/$b.u.mp4
  ffmpeg -v error -y -i $f -c copy $O/$b.d.mp4
  ffprobe -hide_banner $O/$b.u.mp4 > $O/$b.u.probe 2>&1
  ffprobe -hide_banner $O/$b.d.mp4 > $O/$b.d.probe 2>&1
done
