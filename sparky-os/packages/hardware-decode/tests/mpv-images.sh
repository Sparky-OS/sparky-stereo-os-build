#!/bin/sh
set -eu
for name in h264-eyes8 hevc-eyes10 hevc-eyes12 h264-right8 h264-2d8; do
    for mode in no auto; do
        dir=/w/final/$GPU-images/$name-$mode
        mkdir -p "$dir"
        /w/mpv-build/mpv --no-config --hwdec=$mode --vo=image --vo-image-format=png --vo-image-high-bit-depth=yes --vo-image-png-compression=0 --vo-image-outdir="$dir" --ao=null --untimed --frames=3 /w/fixtures/$name.mkv > "$dir/log.txt" 2>&1
    done
done
