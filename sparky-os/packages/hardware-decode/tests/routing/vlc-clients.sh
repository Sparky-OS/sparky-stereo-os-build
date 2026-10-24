#!/bin/sh
set -eu
unset __EGL_VENDOR_LIBRARY_FILENAMES MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME
export WAYLAND_DISPLAY=order223-route
probes=/prev
export LD_LIBRARY_PATH=/w/route-prefix/lib:/prev/ffmpeg-build/libavcodec:/usr/lib/x86_64-linux-gnu/vlc-stereo
if [ "${ROUTE_INSTALLED:-0}" = 1 ]; then
 probes=/w/probes
 export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/vlc-stereo
fi
export LD_PRELOAD=$probes/decoder-trace.so VLC_PLUGIN_PATH=/usr/lib/x86_64-linux-gnu/vlc-stereo/vlc/plugins
mkdir -p /w/final/$SCENARIO
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8; do
 case "$name" in *12) bits=12;; *10) bits=10;; *) bits=8;; esac
 export DECODER_TRACE=/w/final/$SCENARIO/vlc-$name.trace
 "$probes/vlc-proof" /prev/fixtures/$name.mkv /w/final/$SCENARIO/vlc-$name.raw "$bits" --avcodec-hw=any > /w/final/$SCENARIO/vlc-$name.log 2>&1
done
printf 'all 7 VLC runs passed\n' > /w/final/$SCENARIO/passed.txt
