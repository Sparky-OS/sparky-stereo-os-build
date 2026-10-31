#!/bin/bash
# Sparky Stereo OS: sview 26.9+stereo3d2+lc1 from Sparky-OS/sview (ORDER 312: Stereo KWin's output only), built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/24, +stereo3d2 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /fork the sview clone,
# /prev the earlier +lc1 builds, /archive the link gate's public sources. The commit carries debian/ (a native 3.0
# source package) and its changelog entry; the tests run in the build (dh_auto_test).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
NEWV=26.9+stereo3d2
REV=066e11a43aeeee2cabc006d1be2138ca51c8983c
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
git config --global safe.directory '*'
test "$(git -C /fork show "$REV":debian/changelog | head -1)" = "sview ($NEWV) UNRELEASED; urgency=medium"
mkdir -p /work/plain && cd /work/plain
git -C /fork archive --format=tar --prefix="sview-$NEWV/" "$REV" | tar -x
# the dates of the files are the commit's, so the same commit gives the same source archive
touch -d "@$(git -C /fork log -1 --format=%ct "$REV")" "sview-$NEWV"
dpkg-source -b "sview-$NEWV" >/dev/null
rm -rf "sview-$NEWV"
ls
mkdir -p /work/lc && cd /work/lc
cp /work/plain/* .
dpkg-source -x "sview_$NEWV.dsc" /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit
apt-get -y update >/dev/null 2>&1 || { sleep 10; apt-get -y update >/dev/null; }
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
dpkg-query -W libstereo-declare-dev
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
# one output, Stereo KWin's: no other output module, shader, language file or OpenVR
python3 /tools/check-one-output.py /work/lc/sview_"$NEWV"+lc1_amd64.deb
