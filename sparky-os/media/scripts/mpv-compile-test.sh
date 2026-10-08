#!/bin/bash
set -eu
export HOME=/tmp/home; mkdir -p $HOME
rm -rf /w/build-mpv-test
cd /w/mpv-git
meson setup /w/build-mpv-test . --buildtype=plain --prefix=/usr --auto-features auto -Dbuild-date=false -Dcdda=enabled -Ddvdnav=enabled -Dsndio=disabled -Dlibmpv=true -Dvapoursynth=disabled -Dstereo-declare=enabled 2>&1 | tail -60
nice -n 10 ninja -C /w/build-mpv-test -j3 2>&1 | tail -80
