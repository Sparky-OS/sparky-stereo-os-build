#!/bin/bash
# usage: build-tree.sh <name> <commit> [extra cmake args]: worktree of the series at <commit>, built in /w/<name> (libs, plugin, tests)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
name=$1; commit=$2; shift 2
cd ${SPARKY_SCRATCH:?}/qtmm-lane/fork
rm -rf ${SPARKY_SCRATCH:?}/qtmm-lane/wt-$name; git worktree prune; git worktree add -f ${SPARKY_SCRATCH:?}/qtmm-lane/wt-$name $commit >/dev/null 2>&1
cd ${SPARKY_SCRATCH:?}/qtmm-lane
./dk.sh "mkdir -p /w/b-$name && cd /w/b-$name && export CCACHE_DIR=/w/ccache && cmake -G Ninja -S /w/wt-$name -B . -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/w/prefix-$name -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_LIBRARY_PATH=x86_64-linux-gnu -DQT_QML_NO_CACHEGEN=ON -DQT_BUILD_TESTS=ON -DQT_BUILD_EXAMPLES=OFF -DBUILD_WITH_PCH=OFF -DQT_FEATURE_gstreamer=OFF $* > cfg.log 2>&1 && ninja -j4 ffmpegmediaplugin quickmultimedia MultimediaQuickPrivate Multimedia tst_qvideoframeformat tst_qvideoframe tst_qvideotexturehelper tst_qvideoframecolormanagement tst_qvideobuffers tst_qabstractvideobuffer tst_qvideotransformation tst_qquickvideooutput tst_qquickvideooutput_window tst_qvideoframebackend \$( [ -d /w/wt-$name/tests/auto/integration/qquickvideostereo ] && echo tst_qquickvideostereo ) > build.log 2>&1; tail -3 build.log"
