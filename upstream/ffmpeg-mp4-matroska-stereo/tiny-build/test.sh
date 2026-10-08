#!/bin/sh
cd /w; mkdir -p out
rd() { ffp=$1; f=$2; "$ffp" -hide_banner "$f" 2>&1 | grep -E "Stereo 3D|nvalid|rror" | sed 's/^ *//; s/, primary eye: none//' | tr '\n' '|'; }
echo "== the four probe files (the same MP4 with vexu or st3d hidden, and the boxes swapped)"
printf "%-20s %-52s %s\n" file "unpatched" "with the candidate patch"
for f in probe-original probe-no-vexu probe-no-st3d probe-vexu-first; do
  printf "%-20s %-52s %s\n" $f "$(rd /w/bin-base/ffprobe /p/$f.mp4)" "$(rd /w/bin-patched/ffprobe /p/$f.mp4)"
done
echo
echo "== the lane's Matroska fixtures remuxed to MP4 with -c copy -strict unofficial (st3d when the flags are 0, vexu/stri always), read back"
printf "%-34s %-44s %-44s %s\n" "file (mkv Stereo 3D)" "unpatched readback" "patched readback" ""
for f in /fx/h264-mkv-sm*.mkv /fx/h264-sei-sbs-lr.mkv /fx/h264-plain-sbs-lr.mkv; do
  b=$(basename $f .mkv)
  /w/bin-base/ffmpeg -v error -y -i $f -c copy -strict unofficial /w/out/$b.mp4 2>/dev/null
  src=$(/w/bin-base/ffprobe -hide_banner $f 2>&1 | grep "Stereo 3D:" | sed 's/.*Stereo 3D: //; s/, primary eye: none//' | head -n 1)
  printf "%-34s %-44s %-44s\n" "$b (${src:--})" "$(rd /w/bin-base/ffprobe /w/out/$b.mp4)" "$(rd /w/bin-patched/ffprobe /w/out/$b.mp4)"
done
