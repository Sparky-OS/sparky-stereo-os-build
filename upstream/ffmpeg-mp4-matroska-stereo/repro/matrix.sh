#!/bin/sh
# For every Matroska fixture of the ArtCraft lane: how FFmpeg reads it (SAR, stereo side data), then the remux to MP4 with
# -c copy (default strictness and -strict unofficial), what boxes the muxer wrote, and how FFmpeg reads the result back.
cd /out
ffmpeg -version | head -1
printf "%-34s %-22s %-34s | %-26s %-34s\n" file mkv-SAR mkv-stereo "mp4(-strict unofficial)-boxes" readback
for f in /fx/h264-mkv-sm*.mkv /fx/h264-sei-sbs-lr.mkv /fx/h264-plain-sbs-lr.mkv; do
  b=$(basename $f .mkv)
  sar=$(ffprobe -v error -select_streams v:0 -show_entries stream=sample_aspect_ratio -of csv=p=0 $f)
  st=$(ffprobe -hide_banner $f 2>&1 | grep "Stereo 3D:" | sed 's/.*Stereo 3D: //;s/, primary.*//')
  ffmpeg -v error -y -i $f -c copy -strict unofficial /out/$b.u.mp4
  ffmpeg -v error -y -i $f -c copy /out/$b.d.mp4
  boxes=$(python3 /out/boxes.py /out/$b.u.mp4 | grep -E " (st3d|vexu|stri|pasp|sv3d) " | awk '{printf "%s%s ", $1, ($1=="pasp"? "="substr($3,1,0) : "")}' | sed 's/ $//')
  pasp=$(python3 - /out/$b.u.mp4 <<'PY'
import sys, struct
d = open(sys.argv[1], 'rb').read(); i = d.find(b'pasp')
print('%d:%d' % struct.unpack('>II', d[i+4:i+12]) if i > 0 else '-')
PY
)
  rb=$(ffprobe -hide_banner /out/$b.u.mp4 2>&1 | grep "Stereo 3D:" | sed 's/.*Stereo 3D: //;s/, primary.*//')
  rbd=$(ffprobe -hide_banner /out/$b.d.mp4 2>&1 | grep -c "Stereo 3D:")
  printf "%-34s %-22s %-34s | %-26s %-34s (default strictness: %s Stereo 3D lines; pasp %s)\n" $b "$sar" "${st:--}" "$boxes" "${rb:--}" "$rbd" "$pasp"
done
