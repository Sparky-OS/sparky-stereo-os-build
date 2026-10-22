#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/06
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: phoronix-test-suite from upstream's tag v10.8.4, in a throwaway container of Debian testing (amd64; image sparky-pkg-base:amd64 = docker tag of debian:unstable, its suite switched to testing in the script).
# Usage: build.sh [workdir]   (default ${SPARKY_WORKSPACES}/hand-installed-apps/pts/build)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
WORK=${1:-${SPARKY_WORKSPACES:?}/hand-installed-apps/pts/build}
mkdir -p "$WORK"
docker run --rm -e HOST_UID=$(id -u) -v "$WORK":/out -v "$HERE/debian":/debian-ours:ro sparky-pkg-base:amd64 bash -c '
set -e
sed -i "s/^Suites: unstable/Suites: testing testing-updates/" /etc/apt/sources.list.d/debian.sources
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
apt-get update -qq >/dev/null; apt-get install -y -qq ca-certificates git dpkg-dev build-essential fakeroot lintian xz-utils debhelper >/dev/null
cd /out && rm -rf work && mkdir work && cd work
git clone -q --depth 1 --branch v10.8.4 https://github.com/phoronix-test-suite/phoronix-test-suite.git up
echo "tag commit: $(git -C up rev-parse HEAD)"
mkdir phoronix-test-suite-10.8.4
git -C up archive --format=tar HEAD | tar xf - -C phoronix-test-suite-10.8.4
tar --sort=name --mtime=@1789000000 --owner=0 --group=0 -cJf phoronix-test-suite_10.8.4.orig.tar.xz phoronix-test-suite-10.8.4
cp -a /debian-ours phoronix-test-suite-10.8.4/debian
cd phoronix-test-suite-10.8.4
dpkg-buildpackage -us -uc -sa 2>&1 | tail -15
cd .. && lintian -I phoronix-test-suite_*.deb phoronix-test-suite_*.dsc 2>&1 | head -50 > lintian.txt; echo "== lintian"; cat lintian.txt
chown -R $HOST_UID:$HOST_UID /out; ls /out/work
'
