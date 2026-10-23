#!/bin/sh
# NVIDIA container only; compare installed FFmpeg with the rebuilt codec library.
set -eu
mkdir -p /w/final/fallback
set +e
env -u LD_LIBRARY_PATH /w/decode-proof /w/fixtures/hevc-eyes10.mkv cuda-probe-software /w/final/fallback/before.raw 0 > /w/final/fallback/before.csv 2>/w/final/fallback/before.log
result=$?
set -e
printf '%s\n' "$result" > /w/final/fallback/before.exit
[ "$result" = 134 ]
LD_LIBRARY_PATH=/w/ffmpeg-build/libavcodec /w/decode-proof /w/fixtures/hevc-eyes10.mkv cuda-probe-software /w/final/fallback/after.raw 0 > /w/final/fallback/after.csv 2>/w/final/fallback/after.log
printf '%s\n' 0 > /w/final/fallback/after.exit
