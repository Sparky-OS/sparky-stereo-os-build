#!/bin/bash
# Sparky Stereo OS: builds the DRM and stereo autotests of the kwin source that build.sh unpacked and runs them offscreen.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; test.sh starts it.
# It builds with BUILD_TESTING=ON (the package itself builds with it off) from /work/lc/source, the tree the package was built from.
trap 'chown -R 1000:1000 /t' EXIT
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update >/dev/null 2>&1
# this round's builds that the repository does not have yet (none once it has them)
if ls /extra/*.deb >/dev/null 2>&1; then
    apt-get -y --no-install-recommends install /extra/*.deb >/t/build-dep.log 2>&1 || { echo extra install failed; exit 1; }
fi
apt-get -y --no-install-recommends build-dep /work/lc/source >>/t/build-dep.log 2>&1 || { echo build-dep failed; exit 1; }
apt-get -y --no-install-recommends install ninja-build xauth xvfb xwayland dbus libei-dev libeis-dev breeze mesa-utils >>/t/build-dep.log 2>&1
[ -f /t/build/build.ninja ] && REUSE=1 || { REUSE=0; rm -rf /t/build; mkdir -p /t/build; }
# testQuickStereo compiles src/scene/stereodepth.cpp itself, which asks libstereo-policy (+stereo3d43)
export CPATH=/usr/include/stereo-policy
useradd --create-home --uid 1000 builder 2>/dev/null
chown -R builder:builder /t
cd /t/build
# testTabBoxStereo loads its switcher as a KWin/WindowSwitcher package, whose structure is a plugin of its own
# (src/plugins/kpackage); a test in bin/ finds it in bin/kf6/packagestructure, so it is built with the tests
SUPPORT="kwin_windowswitcher"
TARGETS="testStereoOutputRepaint testColorConversion testMockDrm testMockDrmFrameSequential testDrmCommitThread testMockDrmDisplayPortSequential testMockDrmGlasses testVirtualStereo testStereoPair testMockDrmStereoPair testMockDrmDepthStructures testFrameSequential testStereoDownscale testX11Window testDmabufFormatSwitch testStereoDepthExchange testStereoContent testScreenshotStereo testStereoDepthPinned testStereoDepthPopups testStereoDepthMotion testVirtualStereoProtocol testQuickStereo testFallApartStereo testTabBoxStereo testStereoDepthCoding testStereoDepthEstimate testStereoPattern testVirtualOutputProperties testStereoDepthWallpaper testStereoDepthWallpaperCuts testWorkspaceTeardown"
runuser -u builder -- env HOME=/t CPATH=$CPATH sh -c "cmake -G Ninja /work/lc/source -DBUILD_TESTING=ON -DKWIN_BUILD_KCMS=ON -DQTWAYLANDSCANNER_KDE_EXECUTABLE=/usr/lib/qt6/libexec/qtwaylandscanner -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXE_LINKER_FLAGS='-Wl,--no-as-needed -lstereo-policy -Wl,--as-needed' > /t/cmake.log 2>&1 && nice ninja -j4 $TARGETS $SUPPORT > /t/ninja.log 2>&1" || { tail -n 30 /t/cmake.log; tail -n 30 /t/ninja.log; echo BUILD FAILED; exit 1; }
# the tests that read KWin's D-Bus objects, and testTabBoxStereo, whose Alt+Tab reaches the switcher only through the
# kglobalaccel KWin starts on the session bus, run in a session bus of their own, as KWin's own add_test runs every
# integration test (autotests/integration/CMakeLists.txt)
DBUS_TARGETS="testStereoDepthWallpaperCuts testTabBoxStereo"
for t in $TARGETS; do
    bus=; case " $DBUS_TARGETS " in *" $t "*) bus="dbus-run-session --" ;; esac
    # testStereoDownscale opens EGL's default display, which has no platform without a display server
    out=$(setpriv --reuid=1000 --regid=1000 --groups=44,125 env HOME=/t LANG=C.UTF-8 QT_QPA_PLATFORM=offscreen EGL_PLATFORM=surfaceless XDG_RUNTIME_DIR=/t timeout 300 $bus bin/$t 2>&1); rc=$?
    echo "$out" > /t/$t.log
    echo "$t exit $rc $(echo "$out" | grep -E '^Totals')"
done
