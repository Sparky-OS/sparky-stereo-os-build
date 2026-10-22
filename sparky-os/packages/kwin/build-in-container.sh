#!/bin/bash
# Sparky Stereo OS: kwin 4:6.7.4-2+stereo3d29, the published +stereo3d28 source package plus patches/paired-0001 to 0008, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the published sources, /prev the earlier +lc1 builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s29 && cd s29
cp /src/kwin_6.7.4-2+stereo3d28.dsc /src/kwin_6.7.4-2+stereo3d28.debian.tar.xz /src/kwin_6.7.4.orig.tar.xz /src/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d28.dsc t >/dev/null
cd t
for p in /patches/paired-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
p = Path('debian/changelog')
entry = """kwin (4:6.7.4-2+stereo3d29) UNRELEASED; urgency=medium

  * Stereo pairs of outputs recover instead of freezing or crashing (fork
    Sparky-OS/kwin, branch paired-output-recovery, 9e0417d to 9c25908;
    paired-0001 to paired-0008):
    - a pair split over two GPUs shows each eye on its own output, instead
      of failing every frame, re-probing every connector on every GPU and
      freezing both outputs (paired-0003);
    - a pair on one GPU no longer crashes KWin: its commit stays on one
      commit thread, and a pipeline removed while the commit was in flight
      is skipped (paired-0005, paired-0006);
    - the frame waiting for its partner is released when the pair is
      undone or an output is unplugged, disabled or turned off
      (paired-0002);
    - an output scans out its own buffer again after it leaves a pair
      (paired-0004);
    - a mode change while paired works: the new configuration is tested
      without the pair's shared buffer (paired-0008);
    - the page-flip gap of a pair's commit is logged (paired-0007);
    - five new tests in testMockDrmStereoPair, 19 in all (paired-0001).

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  @DATE@

"""
import email.utils
p.write_text(entry.replace('@DATE@', email.utils.formatdate(localtime=True)) + p.read_text())
CHANGELOG
head -22 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s29/kwin_6.7.4-2+stereo3d29.dsc ../s29/kwin_6.7.4-2+stereo3d29.debian.tar.xz ../s29/kwin_6.7.4.orig.tar.xz ../s29/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d29.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d29+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
