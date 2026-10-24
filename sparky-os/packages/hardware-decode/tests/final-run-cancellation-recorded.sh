#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-cancel-recorded
export LD_PRELOAD=/w/decoder-trace.so
for mode in software hardware; do
    if [ "$mode" = software ]; then
        export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=, MLT_AVFORMAT_HWACCEL=none
        hw=no
    else
        unset QT_FFMPEG_DECODING_HW_DEVICE_TYPES MLT_AVFORMAT_HWACCEL
        hw=auto
    fi
    export DECODER_TRACE=/w/final/$GPU-cancel-recorded/mpv-$mode.trace
    /w/mpv-build/mpv --no-config --vo=null --ao=null --untimed --hwdec=$hw -v /w/fixtures/h264-cancel8.mkv > /w/final/$GPU-cancel-recorded/mpv-$mode.log 2>&1
    export DECODER_TRACE=/w/final/$GPU-cancel-recorded/qt-$mode.trace
    QT_QPA_PLATFORM=offscreen /w/qt-proof /w/fixtures/h264-cancel8.mkv /w/final/$GPU-cancel-recorded/qt-$mode.raw 8 96 > /w/final/$GPU-cancel-recorded/qt-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-cancel-recorded/qt-$mode.exit
    export DECODER_TRACE=/w/final/$GPU-cancel-recorded/mlt-$mode.trace
    MLT_DATA=/usr/share/mlt-7 MLT_PROFILES_PATH=/usr/share/mlt-7/profiles MLT_REPOSITORY=/w/mlt-build/out/lib/mlt LD_LIBRARY_PATH=/w/mlt-build/out/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} /w/mlt-proof /w/fixtures/h264-cancel8.mkv /w/final/$GPU-cancel-recorded/mlt-$mode.raw 8 96 > /w/final/$GPU-cancel-recorded/mlt-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-cancel-recorded/mlt-$mode.exit
done
