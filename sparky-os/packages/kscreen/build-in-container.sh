#!/bin/bash
# Sparky Stereo OS: kscreen 4:6.7.4-1+stereo3d12, the +stereo3d11 source package plus patches/s12-* and the translations of
# the extra menus, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d11 source
# package, /prev the earlier +lc1 builds, /patches this folder's patches, /translations sparky-os/translations, /toolkit sparky-os.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s12 && cd s12
# the plain +stereo3d11 source package, which sparky-os/repo/plain-from-lc.py makes from the published +lc1 source
echo 'dd958957d42f97fc61c128a4a106c558ff21bac2dab3f93f569a6579edfb7939  /src/kscreen_6.7.4-1+stereo3d11.dsc' | sha256sum -c
cp /src/kscreen_6.7.4-1+stereo3d11.dsc /src/kscreen_6.7.4-1+stereo3d11.debian.tar.xz /src/kscreen_6.7.4.orig.tar.xz /src/kscreen_6.7.4.orig.tar.xz.asc .
dpkg-source -x kscreen_6.7.4-1+stereo3d11.dsc t >/dev/null
cd t
for p in /patches/s12-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
# the extra menus' strings in the nine languages, after the catalogs the series already carries
cp /translations/kscreen-wdisplays-menus.po.patch debian/patches/
echo kscreen-wdisplays-menus.po.patch >> debian/patches/series
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d12.txt').read_text()
assert entry.startswith('kscreen (4:6.7.4-1+stereo3d12) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# the files this version adds, with their holder
c = Path('debian/copyright'); s = c.read_text()
anchor = '\nFiles: debian/*\n'
assert s.count(anchor) >= 1, 'no debian/* stanza'
stanza = ('\nFiles: kcm/viewoptions.cpp\n kcm/viewoptions.h\n tests/outputmenus.cpp\n'
          'Copyright: 2026, Daniel Campos Ramos <Capitain_Jack@yahoo.com>\nLicense: GPL-2.0-or-later\n')
i = s.index(anchor)
c.write_text(s[:i] + stanza + s[i:])
CHANGELOG
head -40 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s12/kscreen_6.7.4-1+stereo3d12.dsc ../s12/kscreen_6.7.4-1+stereo3d12.debian.tar.xz ../s12/kscreen_6.7.4.orig.tar.xz ../s12/kscreen_6.7.4.orig.tar.xz.asc .
dpkg-source -x kscreen_6.7.4-1+stereo3d12.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-1+stereo3d12+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
dpkg-query -W libkscreen-dev libkf6screen8 plasma-wayland-protocols 2>/dev/null || true
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
dpkg-query -W libkscreen-dev libkf6screen8
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_SIBLINGS_FILE="${SPARKY_LC_SIBLINGS_FILE:-}" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
