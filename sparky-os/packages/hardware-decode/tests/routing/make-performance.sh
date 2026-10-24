#!/bin/sh
set -eu
mkdir -p /w/fixtures
ffmpeg -nostdin -v warning -stream_loop -1 -i /prev/fixtures/h264-sbs8.mp4 -t 20 -c copy /w/fixtures/perf-3d.mp4
ffmpeg -nostdin -v warning -f lavfi -i testsrc2=size=1920x1080:rate=48 -t 20 -an -c:v libx264 -threads 4 -preset veryfast -crf 20 -pix_fmt yuv420p /w/fixtures/perf-2d1080.mkv
for name in perf-3d.mp4 perf-2d1080.mkv; do
 ffprobe -v error -show_streams -show_format -of json /w/fixtures/$name > /w/fixtures/$name.json
done
