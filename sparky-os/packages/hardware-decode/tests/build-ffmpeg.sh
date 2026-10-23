#!/bin/sh
set -eu
mkdir -p /w/ffmpeg-build
cd /w/ffmpeg-build
/w/sources/ffmpeg-dmo/configure --prefix=/w/ffmpeg-prefix --enable-shared --disable-static --disable-programs --disable-doc --disable-avdevice --disable-avfilter --disable-avformat --disable-swresample --disable-swscale --enable-gpl --enable-ffnvcodec --enable-cuda --enable-vaapi > /w/logs/ffmpeg-configure.log 2>&1
make -j4 libavcodec/libavcodec.so > /w/logs/ffmpeg-build.log 2>&1
