#!/bin/sh
set -eu
unset __EGL_VENDOR_LIBRARY_FILENAMES MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME
export WAYLAND_DISPLAY=order223-route
export LD_LIBRARY_PATH=/w/mlt-build/out/lib:/w/route-prefix/lib:/prev/ffmpeg-build/libavcodec
export LD_PRELOAD=/prev/decoder-trace.so
export QT_PLUGIN_PATH=/w/qt-build/lib/x86_64-linux-gnu/qt6/plugins
export MLT_REPOSITORY=/w/mlt-build/out/lib/mlt MLT_DATA=/usr/share/mlt-7 MLT_PROFILES_PATH=/usr/share/mlt-7/profiles
export QT_LOGGING_RULES='qt.multimedia.ffmpeg.hwaccel.debug=true;qt.multimedia.playbackengine.codec.debug=true'
mkdir -p /w/final/$SCENARIO
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8; do
 case "$name" in *12) bits=12;; *10) bits=10;; *) bits=8;; esac
 frames=48; [ "$name" != h264-cancel8 ] || frames=96
 export DECODER_TRACE=/w/final/$SCENARIO/mlt-$name.trace
 /prev/mlt-proof /prev/fixtures/$name.mkv /w/final/$SCENARIO/mlt-$name.raw "$bits" "$frames" > /w/final/$SCENARIO/mlt-$name.log 2>&1
 export DECODER_TRACE=/w/final/$SCENARIO/qt-$name.trace
 /prev/qt-proof /prev/fixtures/$name.mkv /w/final/$SCENARIO/qt-$name.raw "$bits" "$frames" > /w/final/$SCENARIO/qt-$name.log 2>&1
done
printf 'all 14 decoder runs passed\n' > /w/final/$SCENARIO/passed.txt
