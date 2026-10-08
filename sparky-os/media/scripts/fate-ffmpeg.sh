#!/bin/bash
# FATE in the patched tree of ffmpeg-dmo 10:9.0.2-dmo1+stereo3d2 (the patches are applied with quilt for the run; the libraries of the
# tree are found through LD_LIBRARY_PATH). The 4 reference files of the negative control are copied out of the tree too.
set -u
export HOME=/tmp/home; mkdir -p $HOME
export LC_ALL=C.UTF-8
export QUILT_PATCHES=debian/patches
cd /w/build-ff/ffmpeg-dmo-9.0.2
quilt --quiltrc=/dev/null push -a 2>&1 | tail -1
date -u +"build start %F %T"
nice -n 10 make -j${FATE_JOBS:-2} >/w/logs/fate-make.log 2>&1 && echo "make ok" || { echo "make FAILED"; tail -20 /w/logs/fate-make.log | cut -c1-200; exit 1; }
date -u +"build end %F %T"
mkdir -p /w/fate-ref && for t in h264-frame-packing-order h264-frame-packing-persistence hevc-frame-packing-persistence hevc-frame-packing-lifetime; do cp tests/ref/fate/$t /w/fate-ref/; done
export LD_LIBRARY_PATH=$PWD/libavcodec:$PWD/libavdevice:$PWD/libavfilter:$PWD/libavformat:$PWD/libavutil:$PWD/libswresample:$PWD/libswscale
./ffmpeg -version | head -1
echo "license line of the tree: $(./ffmpeg -L 2>/dev/null | head -1)"
echo "configuration has nonfree: $(./ffmpeg -version | grep -c -e '--enable-nonfree')  has libfdk-aac: $(./ffmpeg -version | grep -c -e 'libfdk')"
echo "aac encoders of the tree:"; ./ffmpeg -hide_banner -encoders 2>/dev/null | grep -i -E " (aac|libfdk_aac)[ ]" | cut -c1-90
date -u +"fate start %F %T"
echo "=== the tests our patches add"
nice -n 10 make -j${FATE_JOBS:-2} -k fate-h264-frame-packing-order fate-h264-frame-packing-temporal fate-h264-frame-packing-poc2 fate-h264-frame-packing-container-only fate-h264-frame-packing-persistence fate-h264-frame-packing-container fate-hevc-frame-packing-persistence fate-hevc-frame-packing-lifetime fate-vvc-frame-packing fate-vvc-frame-packing-container-only SAMPLES=/samples 2>&1 | grep -E "^(TEST|make:|Test )" | cut -c1-200
echo "=== groups: fate-h264 fate-hevc fate-vvc"
nice -n 10 make -j${FATE_JOBS:-2} -k fate-h264 fate-hevc fate-vvc SAMPLES=/samples > /w/logs/fate-groups.log 2>&1
echo "tests run: $(grep -c '^TEST' /w/logs/fate-groups.log)"
grep -E "^make.*Error|^Test .* failed" /w/logs/fate-groups.log | cut -c1-200 | head -12
date -u +"fate end %F %T"
