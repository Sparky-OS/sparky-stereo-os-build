#!/bin/sh
set -eu
ffmpeg -v error -y -i /w/fixtures/h264-eyes8.mkv -map_metadata -1 -c:v libx264 -threads 4 -qp 1 -profile:v high -preset fast -bf 0 -g 48 -x264-params frame-packing=3 -f h264 /w/fixtures/marked.h264
ffmpeg -v error -y -i /w/fixtures/h264-2d8.mkv -map_metadata -1 -vf sidedata=mode=delete:type=STEREO3D -c:v libx264 -threads 4 -qp 1 -profile:v high -preset fast -bf 0 -g 48 -f h264 /w/fixtures/mono.h264
python3 /kit/tests/cancel-fixture.py
ffmpeg -v error -y -r 24 -i /w/fixtures/h264-cancel8.h264 -c copy -bsf:v 'setts=pts=N/(24*TB):dts=N/(24*TB)' -map_metadata -1 -metadata:s:v stereo_mode=mono /w/fixtures/h264-cancel8.mkv
