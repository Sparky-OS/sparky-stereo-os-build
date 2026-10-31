#!/bin/bash
# Sparky Stereo OS: installs one build's qt6-base development packages and runs check-headers.py on them.
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Runs inside a fresh debian:testing container; test.sh starts it. /debs holds the build's .deb files (absent for the Debian
# control), /repo is the edition's tree, /t the results folder.
trap 'chown -R 1000:1000 /t' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if [ -d /debs ]; then
	printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
	printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
	apt-get -y update >/t/apt.log 2>&1
	apt-get -y install --no-install-recommends apt-utils >>/t/apt.log 2>&1
	# the build's own packages, above the edition's published ones
	mkdir /local
	for f in /debs/*.deb; do
		case $f in *-dbgsym_*) ;; *) ln -s "$f" /local/ ;; esac
	done
	(cd /local && apt-ftparchive packages . > Packages && apt-ftparchive -o APT::FTPArchive::Release::Origin=qt6-base-build release . > Release)
	printf 'deb [trusted=yes] file:/local ./\n' > /etc/apt/sources.list.d/build.list
	printf 'Package: *\nPin: release o=qt6-base-build\nPin-Priority: 1002\n' > /etc/apt/preferences.d/build
	expected=$(dpkg-deb -f /debs/qt6-base-dev_*_amd64.deb Version)
fi
apt-get -y update >>/t/apt.log 2>&1
# with the development files of the libraries the private headers include (Qt's own build dependencies), which
# qt6-base-private-dev leaves to the modules that use those headers
apt-get -y install --no-install-recommends qt6-base-dev qt6-base-private-dev g++ pkg-config python3 \
	libatspi2.0-dev libcups2-dev libdouble-conversion-dev libdrm-dev libegl-dev libfreetype-dev libgbm-dev libicu-dev \
	libssl-dev libwayland-dev >>/t/apt.log 2>&1
installed=$(dpkg-query -W -f '${Version}' qt6-base-dev)
echo "qt6-base-dev $installed"
if [ -d /debs ] && [ "$installed" != "$expected" ]; then
	echo "FAIL: qt6-base-dev $installed is installed, not the build's $expected" | tee /t/summary.txt
	exit 1
fi
python3 -I /tools/check-headers.py /t
