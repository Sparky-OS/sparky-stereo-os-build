#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ulimit -c 0
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel="$BUILD_THREADS"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
trap 'chown -R "$BUILD_UID:$BUILD_GID" /work' EXIT
apt-get update --error-on=any
apt-get -y --no-install-recommends install build-essential dpkg-dev devscripts debhelper quilt fakeroot gettext python3 python3-yaml python3-pyelftools nodejs node-acorn ca-certificates bubblewrap
if ! getent passwd builder >/dev/null; then useradd --create-home builder; fi
mkdir /work/build /work/link-scratch
chown builder:builder /work/build /work/link-scratch
runuser -u builder -- dpkg-source -x /source-input/plasma-pa_6.7.4-1+stereo3d4+lc1.dsc /work/build/source
apt-get -y --no-install-recommends build-dep /work/build/source
cd /work/build/source
runuser -u builder -- env DEB_BUILD_OPTIONS="parallel=$BUILD_THREADS" dpkg-buildpackage -b -us -uc -j"$BUILD_THREADS"
# Debian disables its build-time suite. Run the native unit test explicitly;
# Appium requirements and the independently installed UI proofs are recorded.
runuser -u builder -- env QT_QPA_PLATFORM=offscreen ctest --test-dir obj-x86_64-linux-gnu -R '^(percentvalidatortest|soundformatconftest|speakersetupconftest|speakertestsignaltest)$' --output-on-failure
cd /work/build
PYTHONPATH=/build-tree/sparky-os python3 -m lean.release check-debs ./*.deb
