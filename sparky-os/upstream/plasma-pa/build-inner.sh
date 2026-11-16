#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
ulimit -c 0
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
export SPARKY_LC_ARCHIVE_CONFIG=/work19/archive/sources.json SPARKY_LC_SCRATCH=/work19/link-scratch
export SPARKY_LC_PREVIOUS_DIR=/work19/previous
trap 'chown -R 1000:1000 /work19' EXIT
apt-get -y --no-install-recommends build-dep /work19/prepared/lc/source
mkdir /work19/build
chown 1000:1000 /work19/build
runuser -u rig -- dpkg-source -x /work19/prepared/lc/plasma-pa_6.7.4-1+stereo3d1+lc1.dsc /work19/build/source
cd /work19/build/source
runuser -u rig -- env DEB_BUILD_OPTIONS=parallel=2 dpkg-buildpackage -b -us -uc -j2
# Debian disables its build-time suite. Run the native unit test explicitly;
# Appium requirements and the independently installed UI proofs are recorded.
runuser -u rig -- env QT_QPA_PLATFORM=offscreen ctest --test-dir obj-x86_64-linux-gnu -R '^percentvalidatortest$' --output-on-failure
cd /work19/build
PYTHONPATH=/lane/src/sparky-stereo-os-build/sparky-os python3 -m lean.release check-debs ./*.deb
