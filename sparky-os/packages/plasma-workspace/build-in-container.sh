#!/bin/bash
# Sparky Stereo OS: plasma-workspace 4:6.7.4-2+stereo3d3, the +stereo3d2 source package plus patches/s3-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the plain +stereo3d2 source
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
mkdir s3 && cd s3
# the plain +stereo3d2 source package: sparky-os/repo/plain-from-lc.py --no-build-depends --edition-entry on the published
# +stereo3d2+lc1 source (the same bytes each time it is made); its .dsc pins the files
echo '4aa2211c35d940ab8ae0f45ad3d84e562592edff47602ad16007963b9fb66d7c  /src/plasma-workspace_6.7.4-2+stereo3d2.dsc' | sha256sum -c
cp /src/plasma-workspace_6.7.4-2+stereo3d2.dsc /src/plasma-workspace_6.7.4-2+stereo3d2.debian.tar.xz /src/plasma-workspace_6.7.4.orig.tar.xz /src/plasma-workspace_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-workspace_6.7.4-2+stereo3d2.dsc t >/dev/null
cd t
for p in /patches/s3-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d3.txt').read_text()
assert entry.startswith('plasma-workspace (4:6.7.4-2+stereo3d3) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s3/plasma-workspace_6.7.4-2+stereo3d3.dsc ../s3/plasma-workspace_6.7.4-2+stereo3d3.debian.tar.xz ../s3/plasma-workspace_6.7.4.orig.tar.xz ../s3/plasma-workspace_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-workspace_6.7.4-2+stereo3d3.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d3+lc1 --toolkit /toolkit
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
mkdir -p /work/plugin-check && dpkg-deb -x /work/lc/qml6-module-org-kde-plasma-workspace_6.7.4-2+stereo3d3+lc1_amd64.deb /work/plugin-check
ls /work/plugin-check/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/plasma/wallpapers/image/libplasma_wallpaper_image.so
rm -rf /work/plugin-check
