#!/bin/bash
# Sparky Stereo OS: sview 26.9+stereo3d5+lc1 from Sparky-OS/sview (ORDER 312: Stereo KWin's output only; ORDER 349:
# the review corrections of the JPS save and the frame-sequence eye order; ORDER 349b: the reasons said in nine
# languages, PNG's sTER and the save into videos; ORDER 529: shared JPEG/MPO codec and verified temporary
# replacement for every per-file correction, ten languages), built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/24, +stereo3d2 2026/10/31, +stereo3d3 and +stereo3d4 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /fork the sview clone,
# /prev the earlier +lc1 builds, /archive the link gate's public sources. The commit carries debian/ (a native 3.0
# source package) and its changelog entry; the tests run in the build (dh_auto_test).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
ulimit -c 0
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
NEWV=26.9+stereo3d5
REV=f1ccff7be68630bed37709e9e31014c13198082f
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
# Read-only bind of the source; trust only this explicit clone, without changing git configuration.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=/fork
# A native source is dated by its commit, never by the clock (ORDER 421b); the build record says so.
SOURCE_DATE_EPOCH=$(git -C /fork log -1 --format=%ct "$REV")
export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS="the commit $REV of the source repository"
test "$(git -C /fork show "$REV":debian/changelog | head -1)" = "sview ($NEWV) UNRELEASED; urgency=medium"
mkdir -p /work/plain && cd /work/plain
git -C /fork archive --format=tar --prefix="sview-$NEWV/" "$REV" | tar -x
# the dates of the files are the commit's, so the same commit gives the same source archive
touch -d "@$SOURCE_DATE_EPOCH" "sview-$NEWV"
python3 /run/reproducible.py normalize "$SOURCE_DATE_EPOCH" "sview-$NEWV"
dpkg-source -b "sview-$NEWV" >/dev/null
rm -rf "sview-$NEWV"
ls
mkdir -p /work/lc && cd /work/lc
cp /work/plain/* .
dpkg-source -x "sview_$NEWV.dsc" /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit
apt-get -y update >/dev/null 2>&1 || { sleep 10; apt-get -y update >/dev/null; }
if [ -d /policy-candidate ]; then
  apt-get -y --no-install-recommends install /policy-candidate/libstereo-policy1_*.deb /policy-candidate/libstereo-policy-dev_*.deb >>/work/build-dep.log 2>&1
  printf '%s\n' /policy-candidate/libstereo-policy1_*.deb > /work/policy-siblings.txt
  export SPARKY_LC_SIBLINGS_FILE=/work/policy-siblings.txt
fi
apt-get -y --no-install-recommends build-dep /work/lc/source >>/work/build-dep.log 2>&1
dpkg-query -W libstereo-declare-dev
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
# the renderer label and digest of every package against the version table (lean 0.1.24, ORDER 352a)
PYTHONPATH=/toolkit python3 -m lean.release check-identity /work/lc/*+lc1_*.deb
# one output, Stereo KWin's: no other output module, shader, language file or OpenVR
python3 /tools/check-one-output.py /work/lc/sview_"$NEWV"+lc1_amd64.deb
