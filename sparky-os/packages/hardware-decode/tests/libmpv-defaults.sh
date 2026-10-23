#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-libmpv
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8; do
 DECODER_TRACE=/w/final/$GPU-libmpv/$name.trace LD_PRELOAD=/w/decoder-trace.so /w/libmpv-proof /w/fixtures/$name.mkv > /w/final/$GPU-libmpv/$name.log 2>&1
done
