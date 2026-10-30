#!/bin/bash
# Sparky Stereo OS: plasma-workspace 4:6.7.4-2+stereo3d4, the +stereo3d3 source package plus patches/s4-* and
# sparky-os/translations/plasma-workspace-wallpaper-cost.po.patch, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the plain +stereo3d3 source
# package, /prev the earlier +lc1 builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s4 && cd s4
# the plain +stereo3d3 source package, the one the +stereo3d3+lc1 build was made from (ORDER 291, source-plain); its .dsc
# pins the files
echo '919a8a3d47e9e665730b65814050fc46fe0abb0b8af86b7f19c9b29990c54a84  /src/plasma-workspace_6.7.4-2+stereo3d3.dsc' | sha256sum -c
cp /src/plasma-workspace_6.7.4-2+stereo3d3.dsc /src/plasma-workspace_6.7.4-2+stereo3d3.debian.tar.xz /src/plasma-workspace_6.7.4.orig.tar.xz /src/plasma-workspace_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-workspace_6.7.4-2+stereo3d3.dsc t >/dev/null
cd t
for p in /patches/s4-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
# the new strings in the eight languages, on the 6.7.4 tarball's catalogs; last in the series
cp /toolkit/translations/plasma-workspace-wallpaper-cost.po.patch debian/patches/
echo plasma-workspace-wallpaper-cost.po.patch >> debian/patches/series
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d4.txt').read_text()
assert entry.startswith('plasma-workspace (4:6.7.4-2+stereo3d4) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s4/plasma-workspace_6.7.4-2+stereo3d4.dsc ../s4/plasma-workspace_6.7.4-2+stereo3d4.debian.tar.xz ../s4/plasma-workspace_6.7.4.orig.tar.xz ../s4/plasma-workspace_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-workspace_6.7.4-2+stereo3d4.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d4+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
# the image wallpaper reads its image again for a new window
mkdir -p /work/plugin-check && dpkg-deb -x /work/lc/qml6-module-org-kde-plasma-workspace_6.7.4-2+stereo3d4+lc1_amd64.deb /work/plugin-check
ls /work/plugin-check/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/plasma/wallpapers/image/libplasma_wallpaper_image.so
rm -rf /work/plugin-check
