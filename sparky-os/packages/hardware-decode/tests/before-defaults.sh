#!/bin/sh
set -eu
mkdir -p /w/final/before/$GPU
export LD_PRELOAD=/w/decoder-trace.so
export DECODER_TRACE=/w/final/before/$GPU/mpv.trace
mpv --no-config --vo=null --ao=null --untimed -v /w/fixtures/h264-eyes8.mkv > /w/final/before/$GPU/mpv.log 2>&1
export DECODER_TRACE=/w/final/before/$GPU/mlt.trace
MLT_DATA=/usr/share/mlt-7 MLT_PROFILES_PATH=/usr/share/mlt-7/profiles /w/mlt-proof /w/fixtures/h264-eyes8.mkv /w/final/before/$GPU/mlt.raw 8 > /w/final/before/$GPU/mlt.log 2>&1
export DECODER_TRACE=/w/final/before/$GPU/vlc.trace
timeout 15 vlc-stereo -I dummy --vout=dummy --aout=dummy --play-and-exit --no-plugins-cache -vv /w/fixtures/hevc-eyes10.mkv > /w/final/before/$GPU/vlc.log 2>&1
