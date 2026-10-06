#!/bin/bash
# Sparky Stereo OS: libcapi20-3 rebuilt from Debian unstable's source (Debian's packaging as it is).
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/06
# Copyright 2026 under the GNU GPL3 License
# Why: Sparky's wine needs libcapi20-3t64, whose binary is not in Debian testing today
# (source libcapi20-3 1:3.27-3.2 is in unstable and stable; tracker bug #1143331).
# Changes: the changelog entry, the maintainer fields, and the two kernel CAPI headers (compat-include) that
# linux-libc-dev in testing no longer ships, without which configure fails.
# Usage: build.sh [workdir]   (default /K3D/temp/partners/queue/hand-installed-apps/capi/build)
set -euo pipefail
WORK=${1:-/K3D/temp/partners/queue/hand-installed-apps/capi/build}
mkdir -p "$WORK"
HERE=$(dirname "$(readlink -f "$0")")
docker run --rm -e HOST_UID=$(id -u) -v "$WORK":/out -v "$HERE/compat-include":/compat:ro sparky-pkg-base:amd64 bash -c '
set -e
sed -i "s/^Suites: unstable/Suites: testing testing-updates/" /etc/apt/sources.list.d/debian.sources
export DEBIAN_FRONTEND=noninteractive LC_ALL=C DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com DEB_BUILD_OPTIONS=parallel=4
apt-get update -qq >/dev/null; apt-get install -y -qq ca-certificates >/dev/null
printf "Types: deb-src\nURIs: http://deb.debian.org/debian\nSuites: unstable\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n" >/etc/apt/sources.list.d/u.sources
apt-get update -qq >/dev/null
apt-get install -y -qq dpkg-dev devscripts build-essential fakeroot lintian >/dev/null
cd /out && rm -rf work && mkdir work && cd work
apt-get source libcapi20-3 2>&1 | tail -3 || true
cd libcapi20-3-*
cp debian/changelog /out/work/changelog.orig; cp debian/control /out/work/control.orig
CUR=$(dpkg-parsechangelog -S Version)
dch -v "$CUR+sparky1" -D unstable --force-distribution "Rebuilt for Sparky Stereo OS: Sparky wine depends on libcapi20-3t64, whose binary is not in Debian testing (bug #1143331)."
sed -i "s/^Maintainer: \(.*\)/Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-Maintainer: \1/" debian/control
mkdir -p debian/compat-include && cp -a /compat/linux /compat/README debian/compat-include/
printf "\nexport DEB_CPPFLAGS_MAINT_APPEND = -I\$(CURDIR)/debian/compat-include\n" >> debian/rules
cat >> debian/copyright <<X

Files: debian/compat-include/linux/*
Copyright: Linux kernel contributors (Carsten Paeth and others)
License: GPL-2 with Linux-syscall-note
 Copied unchanged from linux-libc-dev 6.12.107-1 (Debian stable); the headers are
 no longer in linux-libc-dev in testing. SPDX: GPL-2.0 WITH Linux-syscall-note.
X
dch -a "debian/compat-include: the two kernel CAPI headers linux-libc-dev no longer ships, used through CPPFLAGS (debian/rules); configure stops without them, which is why the package is not in testing."
apt-get build-dep -y -qq . 2>&1 | tail -1
dpkg-buildpackage -us -uc -sa 2>&1 | tail -6
cd .. && lintian -I libcapi20-3t64_*.deb 2>&1 | head -20 > lintian.txt; cat lintian.txt
chown -R $HOST_UID:$HOST_UID /out; ls /out/work
'
