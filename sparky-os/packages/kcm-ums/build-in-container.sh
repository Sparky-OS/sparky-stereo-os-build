#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/11
# Copyright 2026 under the GNU GPL3 License
# Invoked by build.sh, with authored inputs in /work/plain/source and release tools read-only.
set -euo pipefail
trap 'chown -R "$OWNER" /work' EXIT
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 QT_QPA_PLATFORM=offscreen
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/kcm-ums-repository.asc
printf 'Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/kcm-ums-repository.asc\n' > /etc/apt/sources.list.d/kcm-ums.sources
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/kcm-ums
apt-get -y update
apt-cache policy build-essential debhelper devscripts dpkg-dev python3 bubblewrap
apt-get -y --no-install-recommends install build-essential debhelper devscripts dpkg-dev python3 bubblewrap
builder=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -z "$builder" ]; then useradd --create-home --uid 1000 builder; builder=builder; fi
chown -R 1000:1000 /work
cd /work/plain/source
VERSION=$(dpkg-parsechangelog -S Version)
python3 /run/reproducible.py normalize "$SOURCE_DATE_EPOCH" /work/plain/source
runuser -u "$builder" -- dpkg-buildpackage -S -d -us -uc
mkdir /work/lc
chown 1000:1000 /work/lc
cd /work/lc
runuser -u "$builder" -- dpkg-source -x "/work/plain/kcm-ums_$VERSION.dsc" /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$VERSION+lc1" --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /work/lc/source
python3 /run/reproducible.py normalize "$SOURCE_DATE_EPOCH" /work/lc/source
chown -R 1000:1000 /work/lc
cd /work/lc/source
runuser -u "$builder" -- dpkg-buildpackage -us -uc -j4
cp .sparky-lc/source.json /work/lc/native-source.json
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
PYTHONPATH=/toolkit python3 -m lean.release check-identity ./*+lc1_*.deb
