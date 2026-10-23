#!/bin/sh
set -eu
opts=$(sed -n 's/^option(\(MOD_[A-Z0-9_]*\) .*/-D\1=OFF/p' /prev/sources/mlt/CMakeLists.txt)
cmake -S /prev/sources/mlt -B /w/mlt-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCLANG_FORMAT=OFF -DBUILD_TESTING=OFF $opts -DMOD_AVFORMAT=ON -DMOD_PLUS=ON
cmake --build /w/mlt-build -j4
