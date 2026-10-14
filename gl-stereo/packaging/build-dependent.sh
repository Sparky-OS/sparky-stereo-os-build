#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
while [ ! -f /build/logs/xscreensaver-build.status ]; do sleep 5; done
test "$(cat /build/logs/xscreensaver-build.status)" = 0
apt-get -y --no-install-recommends install \
    /build/sources/xscreensaver-data_6.09+dfsg1-2+stereo3d1_amd64.deb \
    /build/sources/xscreensaver-data-extra_6.09+dfsg1-2+stereo3d1_amd64.deb \
    /build/sources/xscreensaver-gl_6.09+dfsg1-2+stereo3d1_amd64.deb \
    /build/sources/xscreensaver-gl-extra_6.09+dfsg1-2+stereo3d1_amd64.deb
cd /build/sources/gl-stereo-0.2.0
dpkg-buildpackage -us -uc -sa -j4 > /build/logs/gl-stereo-build.log 2>&1 || { echo $? > /build/logs/gl-stereo-build.status; exit 1; }
echo 0 > /build/logs/gl-stereo-build.status
apt-get -y --no-install-recommends install /build/sources/libstereoshow{1,-dev}_0.2.0-1_amd64.deb
bash /workspace/gl-stereo/packaging/build-upstream.sh kscreenlocker > /build/logs/kscreenlocker-build.log 2>&1 || { echo $? > /build/logs/kscreenlocker-build.status; exit 1; }
echo 0 > /build/logs/kscreenlocker-build.status
