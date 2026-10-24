#!/bin/bash
# Sparky Stereo OS: qt6-base 6.11.2+dfsg-5+stereo3d11, the +stereo3d7 source package plus the s8, side-by-side, view-size and EGL content-pair patches, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d7 source package, /prev the earlier +lc1 builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s11 && cd s11
# the +stereo3d7 source package as it was built and published (its .dsc pins the files)
echo 'f17f27a9ff8280653e9b6f83bdf2b0cf1731df997d6f7cbea4d1c022faa416b6  /src/qt6-base_6.11.2+dfsg-5+stereo3d7.dsc' | sha256sum -c
cp /src/qt6-base_6.11.2+dfsg-5+stereo3d7.dsc /src/qt6-base_6.11.2+dfsg-5+stereo3d7.debian.tar.xz /src/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d7.dsc t >/dev/null
cd t
for p in /patches/s8-*.patch /patches/stereo3d-wayland-side-by-side-views.patch \
         /patches/stereo3d-wayland-view-size.patch /patches/stereo3d-wayland-egl-content-pair.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
# s8-0001 carries kde-stereo-content-v1.xml in 3rdparty; Qt installs it beside the other Wayland protocols
python3 - <<'INSTALL'
from pathlib import Path
p = Path('debian/qt6-base-dev.install')
lines = p.read_text().splitlines()
new = ['usr/share/qt6/wayland/protocols/kde-stereo-content/REUSE.toml',
       'usr/share/qt6/wayland/protocols/kde-stereo-content/kde-stereo-content-v1.xml',
       'usr/share/qt6/wayland/protocols/kde-stereo-content/qt_attribution.json']
assert not set(new) & set(lines)
at = next(i for i, l in enumerate(lines) if l.startswith('usr/share/qt6/wayland/protocols/') and l > new[0])
p.write_text('\n'.join(lines[:at] + new + lines[at:]) + '\n')
INSTALL
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
for revision in (8, 9, 10, 11):
    entry = Path(f'/tools/changelog-stereo3d{revision}.txt').read_text()
    assert entry.startswith(f'qt6-base (6.11.2+dfsg-5+stereo3d{revision}) unstable;'), entry[:60]
    p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s11/qt6-base_6.11.2+dfsg-5+stereo3d11.dsc ../s11/qt6-base_6.11.2+dfsg-5+stereo3d11.debian.tar.xz ../s11/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d11.dsc /work/lc/source >/dev/null
cd /work/lc/source
# The same source-consumer plan as the published +stereo3d7+lc1 (sparky-os/release/run-native-batch.py).
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.11.2+dfsg-5+stereo3d11+lc1 --toolkit /toolkit \
	--preserve-source 'src/*_p.h' 'Qt syncqt reads the private-API warning comments, including We mean it.; retain its input headers exactly' \
	--preserve-source 'tests/*' 'Qt test inputs include deliberate comment/splice and invalid-syntax fixtures consumed as text by qmake and moc; preserve the upstream test corpus while projecting production source' \
	--preserve-source 'src/corelib/global/qoperatingsystemversion.h' 'Qt syncqt generates a different public-header set after textual projection; retain this input exactly, verified by the authored/projected syncqt comparison'
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
