#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-engines
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8; do
    bits=$(printf '%s' "$name" | sed 's/.*[^0-9]//')
    for mode in software hardware; do
        if [ "$mode" = software ]; then
            export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=,
            export MLT_AVFORMAT_HWACCEL=none
        else
            unset QT_FFMPEG_DECODING_HW_DEVICE_TYPES MLT_AVFORMAT_HWACCEL
        fi
        export LD_PRELOAD=/w/decoder-trace.so
        export DECODER_TRACE=/w/final/$GPU-engines/qt-$name-$mode.trace
        QT_QPA_PLATFORM=offscreen QT_LOGGING_RULES='qt.multimedia.ffmpeg.hwaccel.debug=true;qt.multimedia.playbackengine.codec.debug=true' /w/qt-proof /w/fixtures/$name.mkv /w/final/$GPU-engines/qt-$name-$mode.raw "$bits" > /w/final/$GPU-engines/qt-$name-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-engines/qt-$name-$mode.exit
        export DECODER_TRACE=/w/final/$GPU-engines/mlt-$name-$mode.trace
        MLT_DATA=/usr/share/mlt-7 MLT_PROFILES_PATH=/usr/share/mlt-7/profiles MLT_REPOSITORY=/w/mlt-build/out/lib/mlt LD_LIBRARY_PATH=/w/mlt-build/out/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} /w/mlt-proof /w/fixtures/$name.mkv /w/final/$GPU-engines/mlt-$name-$mode.raw "$bits" > /w/final/$GPU-engines/mlt-$name-$mode.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-engines/mlt-$name-$mode.exit
    done
done
