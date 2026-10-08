#!/bin/sh
# what FFmpeg's own Matroska muxer writes for a side-by-side stream, and how it reads it back
cd /out
ffmpeg -version | head -1
# a full side by side clip: two 640x360 eyes in 1280x360 square pixels (the lane's plain clip), then stamped stereo_mode=left_right
ffmpeg -v error -y -i /fx/h264-plain-sbs-lr.mkv -c copy -metadata:s:v:0 stereo_mode=left_right /out/ffmuxed-sbs.mkv
ffmpeg -v error -y -i /fx/h264-plain-sbs-lr.mkv -c copy -metadata:s:v:0 stereo_mode=top_bottom /out/ffmuxed-tb-on-sbs.mkv
for f in ffmuxed-sbs ffmuxed-tb-on-sbs; do
  echo "== $f.mkv read by FFmpeg"; ffprobe -hide_banner /out/$f.mkv 2>&1 | grep -E "Stream|stereo_mode|Stereo 3D"
done
