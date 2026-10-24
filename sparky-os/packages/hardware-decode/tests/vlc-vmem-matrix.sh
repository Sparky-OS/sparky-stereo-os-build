#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-vlc-vmem
export LD_PRELOAD=/w/decoder-trace.so
export VLC_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/vlc-stereo/vlc/plugins
export LD_LIBRARY_PATH=/w/ffmpeg-build/libavcodec:/usr/lib/x86_64-linux-gnu/vlc-stereo
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8; do
    bits=$(printf '%s' "$name" | sed 's/.*[^0-9]//')
    for mode in none any; do
        export DECODER_TRACE=/w/final/$GPU-vlc-vmem/$name-$mode.trace
        /w/vlc-proof /w/fixtures/$name.mkv /w/final/$GPU-vlc-vmem/$name-$mode.raw "$bits" --avcodec-hw=$mode > /w/final/$GPU-vlc-vmem/$name-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-vlc-vmem/$name-$mode.exit
    done
done
