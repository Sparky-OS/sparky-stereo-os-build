#!/bin/bash
# In the mdmo-ffbuild386 container (native i386), as the user: build our source package (the i386 twin)
set -eu
export HOME=/tmp/home; mkdir -p $HOME
export DEB_BUILD_OPTIONS="nocheck parallel=4"
export LC_ALL=C.UTF-8
cd /w/build-ff386
cp /w/srcpkg2/ffmpeg-dmo_9.0.2* . 2>/dev/null || true
dpkg --print-architecture
dpkg-source -x ffmpeg-dmo_9.0.2-dmo1+stereo3d2.dsc 2>&1 | tail -3
ls
cd ffmpeg-dmo-9.0.2
echo "libfdk-aac-dev installed in this build environment: $(dpkg -s libfdk-aac-dev 2>/dev/null | grep -c '^Status: install ok installed')"
dpkg-checkbuilddeps -B && echo "build dependencies satisfied"
date -u +"build start %F %T"
time nice -n 10 dpkg-buildpackage -B -us -uc -d 2>&1
date -u +"build end %F %T"
