#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-more
export LD_PRELOAD=/w/decoder-trace.so
for name in mpeg2-eyes8 vp9-eyes8 vp9-eyes10; do
    bits=$(printf '%s' "$name" | sed 's/.*[^0-9]//')
    export DECODER_TRACE=/w/final/$GPU-more/mpv-$name.trace
    /w/mpv-build/mpv --no-config --vo=null --ao=null --untimed -v /w/fixtures/$name.mkv > /w/final/$GPU-more/mpv-$name.log 2>&1
    for mode in software hardware; do
        if [ "$mode" = software ]; then
            export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=, MLT_AVFORMAT_HWACCEL=none
        else
            unset QT_FFMPEG_DECODING_HW_DEVICE_TYPES MLT_AVFORMAT_HWACCEL
        fi
        export DECODER_TRACE=/w/final/$GPU-more/qt-$name-$mode.trace
        QT_QPA_PLATFORM=offscreen /w/qt-proof /w/fixtures/$name.mkv /w/final/$GPU-more/qt-$name-$mode.raw "$bits" > /w/final/$GPU-more/qt-$name-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-more/qt-$name-$mode.exit
        export DECODER_TRACE=/w/final/$GPU-more/mlt-$name-$mode.trace
        MLT_DATA=/usr/share/mlt-7 MLT_PROFILES_PATH=/usr/share/mlt-7/profiles MLT_REPOSITORY=/w/mlt-build/out/lib/mlt LD_LIBRARY_PATH=/w/mlt-build/out/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} /w/mlt-proof /w/fixtures/$name.mkv /w/final/$GPU-more/mlt-$name-$mode.raw "$bits" > /w/final/$GPU-more/mlt-$name-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-more/mlt-$name-$mode.exit
    done
done
