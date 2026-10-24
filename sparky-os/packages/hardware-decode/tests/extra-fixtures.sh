#!/bin/sh
set -eu
ffmpeg -v error -y -i /w/fixtures/h264-eyes8.mkv -map_metadata -1 -vf sidedata=mode=delete:type=STEREO3D -c:v libx264 -threads 4 -qp 1 -profile:v high -preset fast -metadata:s:v stereo_mode=mono /w/fixtures/h264-2d8.mkv
ffmpeg -v error -y -i /w/fixtures/h264-eyes8.mkv -filter_complex '[0:v]split[a][b];[a]crop=iw/2:ih:iw/2:0[r];[b]crop=iw/2:ih:0:0[l];[r][l]hstack,sidedata=mode=delete:type=STEREO3D' -map_metadata -1 -c:v libx264 -threads 4 -qp 1 -profile:v high -preset fast /w/fixtures/right-first-unmarked.mkv
ffmpeg -v error -y -i /w/fixtures/right-first-unmarked.mkv -c:v copy -bsf:v h264_metadata=frame_packing=insert:frame_packing_type=side_by_side:frame_packing_view=right_first /w/fixtures/h264-right8.mkv
ffmpeg -v error -y -i /w/fixtures/h264-eyes8.mkv -c copy -bsf:v h264_mp4toannexb /w/fixtures/marked.h264
ffmpeg -v error -y -i /w/fixtures/h264-2d8.mkv -c copy -bsf:v h264_mp4toannexb /w/fixtures/mono.h264
python3 /kit/tests/cancel-fixture.py
