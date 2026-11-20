#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Container-only fixture, from a separately signature-verified FFmpeg source tree.
set -eu
source_tree=${1:?verified FFmpeg source directory}
prefix=${2:?private scratch installation prefix}
cd "$source_tree"
./configure --prefix="$prefix" --disable-everything --disable-programs --disable-doc --disable-static --enable-shared --disable-x86asm --enable-decoder=h264,aac --enable-parser=h264,aac --enable-demuxer=mov --enable-protocol=file
make -j4
make install
