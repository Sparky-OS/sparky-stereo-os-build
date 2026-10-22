#!/bin/bash
# Run inside the isolated migration container. The host checkout is read-only.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
dpkg-source -x /original/stereo-create_1.0.0-1.dsc source
apt-get -y update
apt-get -y --no-install-recommends build-dep /work/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd source
runuser -u builder -- cmake -S . -B build -G Ninja -DBUILD_TESTING=ON
runuser -u builder -- cmake --build build -j4
set +e
runuser -u builder -- env QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure > /work/authored-baseline.log 2>&1
baseline=$?
set -e
test "$baseline" -ne 0
grep -F "'byShape.stereo' returned FALSE" /work/authored-baseline.log
cp /fixed/autotests/enginetest.cpp autotests/enginetest.cpp
runuser -u builder -- cmake --build build -j4
runuser -u builder -- env QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure > /work/corrected-fixture.log 2>&1
printf '{"authored_baseline_exit":%s,"corrected_fixture_exit":0,"lean_projection":false}\n' "$baseline" > /work/result.json
