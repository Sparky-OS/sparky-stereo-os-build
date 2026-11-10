#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/10
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 504: the next +stereo3dN+lc1 of a KDE application (gwenview, kio-extras) with one more patch, inside the Lean Code migration
# container, after the way of spatial-video-rebuilds/gwenview-stereo3d8-build.sh. Mounts: /stage staged debs (stereo-layer), /in the published
# +lc1 source set, /patch the patch, /toolkit sparky-os, /prev the published debs of the package (link gate), /out. Environment: PKG, OLD (old
# version), NEW (new version without +lc1), PATCH (file name), ITEM (changelog text).
set -euo pipefail
REPRO=/toolkit/repo/reproducible.py
: "${SOURCE_DATE_EPOCH:?run through build.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p /repo && cd /repo && cp /stage/*/*.deb . && dpkg-scanpackages -m . 2>/dev/null > Packages
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/staged.list
printf 'Package: *\nPin: origin ""\nPin-Priority: 1002\n' > /etc/apt/preferences.d/staged
printf 'deb [trusted=yes] file:/edition mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends install devscripts quilt xz-utils >/dev/null 2>&1
mkdir -p /out/lc && cd /out/lc && cp /in/* .
dpkg-source -x "$PKG"_*"$OLD"+lc1.dsc src >/dev/null 2>&1
cd src
python3 - <<PY
import os
s=open('debian/changelog').read()
head=s.split('\n',1)[0]
old=head.split('(')[1].split(')')[0]
assert old.endswith('+lc1'), head
s=s.replace(head, head.replace(old, old[:-4]).replace('UNRELEASED','unstable'),1)
s=s.replace("  * Apply verified native Lean Code before compilation and qualified lc1\n    payload assembly; retain exact authored source and HR companions.\n","",1)
open('debian/changelog','w').write(s)
r=open('debian/rules').read(); m='# Distribution-only processing; authored source remains in the source archive.'
assert r.count(m)==1; open('debian/rules','w').write(r.split(m)[0].rstrip('\n')+'\n')
PY
rm -rf debian/sparky-lean-toolkit
cp "/patch/$PATCH" "debian/patches/$PATCH"
echo "$PATCH" >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push -a -q >/dev/null || true
quilt applied | tail -1
dch --date "$SOURCE_DATE_RFC2822" --newversion "$NEW" --distribution unstable "$ITEM"
PYTHONPATH=/toolkit python3 -m lean.debian_prepare . "$NEW+lc1" --toolkit /toolkit
head -12 debian/changelog
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /out/lc/src > /out/build-dep.log 2>&1 || { tail -20 /out/build-dep.log; exit 1; }
useradd --create-home --uid 1000 builder 2>/dev/null || true
chown -R builder /out
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" /out/lc/src
runuser -u builder -- bash -c 'cd /out/lc/src && dpkg-buildpackage -S -us -uc -d > /out/source.log 2>&1'
cd /out/lc && dpkg-source -x "$PKG"_*"${NEW#*:}"+lc1.dsc src2 >/dev/null 2>&1; chown -R builder /out
cd src2
mkdir -p "$SPARKY_LC_SCRATCH"; chown builder "$SPARKY_LC_SCRATCH"
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt SPARKY_LC_SIBLINGS_FILE=/siblings.txt SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -b -j4 > /out/build.log 2>&1 || { echo BUILD-FAILED; tail -30 /out/build.log; }
cd /out/lc && PYTHONPATH=/toolkit python3 -m lean.release check-debs /out/lc/*+lc1_*.deb
chown -R 1000:1000 /out
ls /out/lc
