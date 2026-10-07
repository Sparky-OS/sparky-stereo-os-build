#!/bin/bash
# configure the dev tree (ninja) of the git-managed source; tests on
./dk.sh 'mkdir -p /w/dev && cd /w/dev && export CCACHE_DIR=/w/ccache && cmake -G Ninja -S /w/src/qt6-multimedia-6.11.2 -B . -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/w/prefix -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_LIBRARY_PATH=x86_64-linux-gnu -DQT_QML_NO_CACHEGEN=ON -DQT_BUILD_TESTS=ON -DQT_BUILD_EXAMPLES=OFF -DBUILD_WITH_PCH=OFF -DQT_FEATURE_gstreamer=OFF > cfg.log 2>&1; tail -40 cfg.log'
