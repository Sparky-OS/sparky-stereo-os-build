#!/bin/sh
set -eu
ffmpeg -v error -y -i /w/fixtures/h264-eyes8.mkv -c:v mpeg2video -threads 4 -q:v 2 -metadata:s:v stereo_mode=left_right /w/fixtures/mpeg2-eyes8.mkv
ffmpeg -v error -y -i /w/fixtures/h264-eyes8.mkv -c:v libvpx-vp9 -threads 4 -row-mt 1 -deadline realtime -cpu-used 6 -lossless 1 -metadata:s:v stereo_mode=left_right /w/fixtures/vp9-eyes8.mkv
ffmpeg -v error -y -i /w/fixtures/hevc-eyes10.mkv -c:v libvpx-vp9 -threads 4 -row-mt 1 -deadline realtime -cpu-used 6 -lossless 1 -metadata:s:v stereo_mode=left_right /w/fixtures/vp9-eyes10.mkv
