#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-vlc
export LD_PRELOAD=/w/decoder-trace.so
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8; do
    export DECODER_TRACE=/w/final/$GPU-vlc/$name.trace
    export DECODER_COPY_PIXELS=/w/final/$GPU-vlc/$name.raw
    export DECODER_COPY_TRACE=/w/final/$GPU-vlc/$name-copy.trace
    timeout 15 vlc-stereo -I dummy --vout=dummy --aout=dummy --play-and-exit --no-plugins-cache --no-osd --no-video-title-show -vv /w/fixtures/$name.mkv > /w/final/$GPU-vlc/$name.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-vlc/$name.exit
done
export DECODER_TRACE=/w/final/$GPU-vlc/explicit-none.trace
unset DECODER_COPY_PIXELS DECODER_COPY_TRACE
timeout 15 vlc-stereo -I dummy --vout=dummy --aout=dummy --play-and-exit --no-plugins-cache --avcodec-hw=none -vv /w/fixtures/h264-eyes8.mkv > /w/final/$GPU-vlc/explicit-none.log 2>&1
