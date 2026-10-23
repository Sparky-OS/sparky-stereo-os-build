#!/bin/sh
set -eu
cd /w/sources/vlc
autoreconf -fi > /w/logs/vlc-autoreconf.log 2>&1
mkdir -p /w/vlc-build
cd /w/vlc-build
/w/sources/vlc/configure --disable-nls --disable-lua --disable-qt --disable-skins2 --disable-mad --disable-a52 --disable-mpeg2 --disable-dbus --disable-archive --enable-avcodec > /w/logs/vlc-configure.log 2>&1
make -j4 -C modules libavcodec_plugin.la > /w/logs/vlc-plugin-build.log 2>&1
