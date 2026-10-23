#!/bin/sh
set -eu
meson setup /w/mpv-build /w/sources/mpv-dmo --buildtype=debugoptimized -Dbuild-date=false -Dtests=true -Dstereo-policy=enabled -Dstereo-declare=enabled -Dstereo-dibr=enabled -Dlibmpv=true -Dvapoursynth=disabled
ninja -C /w/mpv-build -j4
