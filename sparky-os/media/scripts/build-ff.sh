#!/bin/bash
# In the mdmo-ffbuild container, as the user: build our ffmpeg-dmo source package tree (arch-dependent packages).
set -eu
export HOME=/tmp/home; mkdir -p $HOME
export DEB_BUILD_OPTIONS="nocheck parallel=4"
export LC_ALL=C.UTF-8
cd /w/build-ff/ffmpeg-dmo-9.0.2
echo "libfdk-aac-dev installed in this build environment: $(dpkg -s libfdk-aac-dev 2>/dev/null | grep -c '^Status: install ok installed')"
dpkg-checkbuilddeps -B && echo "build dependencies satisfied"
date -u +"build start %F %T"
time nice -n 10 dpkg-buildpackage -B -us -uc -d 2>&1
date -u +"build end %F %T"
