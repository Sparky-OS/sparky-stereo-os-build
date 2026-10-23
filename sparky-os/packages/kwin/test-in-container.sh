#!/bin/bash
# Sparky Stereo OS: builds the DRM and stereo autotests of the kwin source that build.sh unpacked and runs them offscreen.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; test.sh starts it.
# It builds with BUILD_TESTING=ON (the package itself builds with it off) from /work/lc/source, the tree the package was built from.
trap 'chown -R 1000:1000 /t' EXIT
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/t/build-dep.log 2>&1 || { echo build-dep failed; exit 1; }
apt-get -y --no-install-recommends install ninja-build xauth xvfb xwayland dbus libei-dev libeis-dev breeze mesa-utils >>/t/build-dep.log 2>&1
[ -x /t/build/bin/testMockDrmStereoPair ] && REUSE=1 || { REUSE=0; rm -rf /t/build; mkdir -p /t/build; }
useradd --create-home --uid 1000 builder 2>/dev/null
chown -R builder:builder /t
cd /t/build
TARGETS="testStereoOutputRepaint testMockDrm testMockDrmFrameSequential testVirtualStereo testStereoPair testMockDrmStereoPair testMockDrmDepthStructures testFrameSequential testStereoDownscale testX11Window testDmabufFormatSwitch testStereoDepthExchange testStereoContent testScreenshotStereo testStereoDepthPinned testStereoDepthPopups testStereoDepthMotion testVirtualStereoProtocol testQuickStereo testFallApartStereo testTabBoxStereo testStereoDepthCoding testStereoDepthEstimate testStereoPattern testVirtualOutputProperties"
[ "$REUSE" = 1 ] || runuser -u builder -- env HOME=/t sh -c "cmake -G Ninja /work/lc/source -DBUILD_TESTING=ON -DKWIN_BUILD_KCMS=ON -DQTWAYLANDSCANNER_KDE_EXECUTABLE=/usr/lib/qt6/libexec/qtwaylandscanner -DCMAKE_BUILD_TYPE=RelWithDebInfo > /t/cmake.log 2>&1 && nice ninja -j4 $TARGETS > /t/ninja.log 2>&1" || { tail -n 30 /t/cmake.log; tail -n 30 /t/ninja.log; echo BUILD FAILED; exit 1; }
for t in $TARGETS; do
    # testStereoDownscale opens EGL's default display, which has no platform without a display server
    out=$(setpriv --reuid=1000 --regid=1000 --groups=$(stat -c %g /dev/dri/renderD128)$([ -c /dev/udmabuf ] && echo ,$(stat -c %g /dev/udmabuf)) env HOME=/t LANG=C.UTF-8 QT_QPA_PLATFORM=offscreen EGL_PLATFORM=surfaceless XDG_RUNTIME_DIR=/t timeout 300 bin/$t 2>&1); rc=$?
    echo "$out" > /t/$t.log
    echo "$t exit $rc $(echo "$out" | grep -E '^Totals')"
done
