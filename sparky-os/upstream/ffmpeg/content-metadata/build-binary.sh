#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DEBEMAIL=Capitain_Jack@yahoo.com
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS=parallel=4
input=${1:?new source package directory}
work=${2:?new architecture build directory}
mode=${3:--B}
case "$mode" in -B|-b) ;; *) echo 'Use -b once for architecture-independent packages; -B otherwise.' >&2; exit 2;; esac
mkdir -p "$work"
dpkg-source -x "$input/ffmpeg-dmo_9.0.2-dmo1+stereo3d7+lc1.dsc" "$work/source"
cd "$work/source"
dpkg-buildpackage "$mode" -us -uc
LD_LIBRARY_PATH="$PWD/libavformat:$PWD/libavcodec:$PWD/libavutil:$PWD/libswresample" make -j4 fate-mov-stereo
