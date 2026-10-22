#!/bin/sh
# Builds sbs2mpo beside this script against the installed Qt 6 (the MPO writer comes from
# KImageFormats' stereo plugin, which reads the Stereo3DLayout key).
# Needs g++ and the Qt 6 Gui development files (qt6-base-dev).
# Usage: build.sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
g++ -O2 -fPIC -o "$HERE/sbs2mpo" "$HERE/sbs2mpo.cpp" $(pkg-config --cflags --libs Qt6Gui)
echo "$HERE/sbs2mpo"
