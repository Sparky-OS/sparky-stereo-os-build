#!/bin/sh
set -eu
mkdir -p /w/final/$GPU-vlc-qt
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8 mpeg2-eyes8 vp9-eyes8 vp9-eyes10; do
    export DECODER_TRACE=/w/final/$GPU-vlc-qt/$name.trace
    timeout 15 vlc-stereo -I qt --no-qt-privacy-ask --no-qt-error-dialogs --aout=dummy --no-osd --no-video-title-show --play-and-exit --no-plugins-cache --no-drop-late-frames -vv /w/fixtures/$name.mkv > /w/final/$GPU-vlc-qt/$name.log 2>&1 || printf '%s\n' "$?" > /w/final/$GPU-vlc-qt/$name.exit
done
