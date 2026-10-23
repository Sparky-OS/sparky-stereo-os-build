#!/bin/sh
set -eu
mkdir -p /w/final/$GPU
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8; do
    DECODER_TRACE=/w/final/$GPU/mpv-$name.trace LD_PRELOAD=/w/decoder-trace.so /w/mpv-build/mpv --no-config --vo=null --ao=null --untimed -v /w/fixtures/$name.mkv > /w/final/$GPU/mpv-$name.log 2>&1
    /w/decode-proof /w/fixtures/$name.mkv software /w/final/$GPU/$name-software.raw 0 > /w/final/$GPU/$name-software.csv 2> /w/final/$GPU/$name-software.err
    if [ "$name" = h264-eyes8 ] || [ "$name" = hevc-eyes10 ] || [ "$name" = h264-2d8 ] || { [ "$GPU" = nvidia ] && [ "$name" = hevc-eyes12 ]; }; then
        /w/decode-proof /w/fixtures/$name.mkv $API /w/final/$GPU/$name-hardware.raw 1 > /w/final/$GPU/$name-hardware.csv 2> /w/final/$GPU/$name-hardware.err || printf '%s\n' "$?" > /w/final/$GPU/$name-hardware.exit
    fi
done
