#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" != 0
repo=$PWD
mkdir -p out/plasma
if [[ ! -f out/plasma/kscreenlocker.tar.gz ]]; then
    curl -fL --max-time 120 -o out/plasma/kscreenlocker.tar.gz https://invent.kde.org/plasma/kscreenlocker/-/archive/v6.7.4/kscreenlocker-v6.7.4.tar.gz
fi
printf '%s\n' '3f7a26b9fcf36a4148f32148569fe6b59b9b11c4365a94a996e07502eec8fa32  out/plasma/kscreenlocker.tar.gz' | sha256sum -c -
if ! patch --dry-run -R -p1 -d out/plasma/kscreenlocker-v6.7.4 < plasma/patches/kscreenlocker-stereo-background.patch >/dev/null 2>&1; then
    tar -xzf out/plasma/kscreenlocker.tar.gz -C out/plasma
    patch -p1 -d out/plasma/kscreenlocker-v6.7.4 < plasma/patches/kscreenlocker-stereo-background.patch
fi
bash plasma/sdk.sh liblayershellqtinterface-dev liblayershellqtinterface6 layer-shell-qt libkworkspace6-6 qml6-module-org-kde-plasma-clock libbatterycontrol6 libkmpris6 libpam-wrapper plasma-workspace
cmake -S out/plasma/kscreenlocker-v6.7.4 -B out/plasma/greeter-build -G Ninja \
    -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_PREFIX_PATH="$repo/out/plasma/build;$repo/out/plasma/prefix;$repo/out/plasma/sdk/usr"
cmake --build out/plasma/greeter-build --target kscreenlocker_greet -j4
mkdir -p out/plasma/share/plasma/shells
cp -a /usr/share/plasma/shells/org.kde.plasma.desktop out/plasma/share/plasma/shells/
patch -p2 -d out/plasma/share/plasma/shells/org.kde.plasma.desktop < plasma/patches/plasma-desktop-stereo-background.patch
