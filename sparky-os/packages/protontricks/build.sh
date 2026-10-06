#!/bin/bash
# Sparky Stereo OS: protontricks 1.15.0 on Debian's packaging (unstable's 1.13.1+ds-1 source).
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Imports upstream's release the way Debian's own packaging does (uscan + the +ds repack of
# debian/copyright's Files-Excluded), keeps debian/ as Debian has it, adds our changelog entry.
# Runs in a throwaway sparky-pkg-base:amd64 container; output in $OUT (source package and .deb).
# Usage: build.sh [workdir]     (default /K3D/temp/partners/queue/hand-installed-apps/ptx/build)
set -euo pipefail
WORK=${1:-/K3D/temp/partners/queue/hand-installed-apps/ptx/build}
NEW=1.15.0
OUR=$NEW+ds-1+sparky1
mkdir -p "$WORK"
docker run --rm -e HOST_UID=$(id -u) -e NEW=$NEW -e OUR=$OUR -v "$WORK":/out -v "$(dirname "$(readlink -f "$0")")/patches":/patches:ro sparky-pkg-base:amd64 bash -c '
set -e
sed -i "s/^Suites: unstable/Suites: testing testing-updates/" /etc/apt/sources.list.d/debian.sources
export DEBIAN_FRONTEND=noninteractive LC_ALL=C DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
apt-get update -qq >/dev/null; apt-get install -y -qq ca-certificates >/dev/null
sed -i "s/^Components: main$/Components: main contrib/" /etc/apt/sources.list.d/debian.sources
printf "Types: deb-src\nURIs: http://deb.debian.org/debian\nSuites: unstable\nComponents: main contrib\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\n" >/etc/apt/sources.list.d/u.sources
apt-get update -qq >/dev/null
apt-get install -y -qq dpkg-dev devscripts build-essential fakeroot lintian xz-utils >/dev/null
cd /out && rm -rf src && mkdir src && cd src
apt-get source --download-only protontricks >/dev/null 2>&1 || true
dpkg-source -x protontricks_1.13.1+ds-1.dsc old >/dev/null
cp -a old/debian /out/debian-1.13.1
cd old
uscan --download-version $NEW --force-download --destdir .. --verbose 2>&1 | tail -5
cd .. ; ls
mkdir new && tar xf protontricks_$NEW+ds.orig.tar.xz -C new --strip-components=1
cp -a old/debian new/
cd new
# debian/patches/remove-usage-of-bundled-vdf.patch refreshed: 1.15.0 moved the code its hunks touch
cp /patches/remove-usage-of-bundled-vdf.patch debian/patches/
dch -v $OUR -D unstable --force-distribution "New upstream version $NEW+ds (imported with uscan and the +ds repack, as debian/watch and debian/copyright say)." 
dch -a "Rebuilt for Sparky Stereo OS: no change to debian/ other than this entry and the maintainer fields."
sed -i "s/^Maintainer: \(.*\)/Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-Maintainer: \1/" debian/control
sed -i "s|^Homepage: https://github.com/Matoking/protontricks|Homepage: https://github.com/Matoking/protontricks|" debian/control
quilt --version >/dev/null 2>&1 || apt-get install -y -qq quilt >/dev/null
diff -ru /out/src/old/debian debian > /out/debian-changes.diff || true
apt-get build-dep -y -qq . 2>&1 | tail -2
dpkg-buildpackage -us -uc -sa 2>&1 | tail -15
cd .. && cp -a protontricks_* /out/ && chown -R $HOST_UID:$HOST_UID /out && ls /out
'
