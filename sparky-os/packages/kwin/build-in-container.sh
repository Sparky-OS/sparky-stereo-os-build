# Sparky Stereo OS: kwin 4:6.7.4-2+stereo3d38, the +stereo3d37 source package plus patches/s38-* and
# sparky-os/translations/kwin-wallpaper-cost.po.patch, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, +stereo3d36 2026/10/29, +stereo3d37 and +stereo3d38 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d37 source package,
# /extra the plasma-wayland-protocols +stereo3d10 build (or nothing once the repository has it), /prev the earlier +lc1 builds,
# /patches this folder's patches, /toolkit the build tree's sparky-os folder (translations/).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s38 && cd s38
# the plain +stereo3d37 source package, the one the +stereo3d37+lc1 build was made from (ORDER 291, source-plain);
# its .dsc pins the files
echo '5c9b8e7926cd623cf48a00683583b37694a37c64b6d0e7bf4f1eb9b2249846d3  /src/kwin_6.7.4-2+stereo3d37.dsc' | sha256sum -c
cp /src/kwin_6.7.4-2+stereo3d37.dsc /src/kwin_6.7.4-2+stereo3d37.debian.tar.xz /src/kwin_6.7.4.orig.tar.xz /src/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d37.dsc t >/dev/null
cd t
for p in /patches/s38-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
# the 3D Depth page's new strings in the eight languages, on the catalogs kwin-stereo-depth.po.patch (earlier in the series)
# makes; last in the series
grep -qx kwin-stereo-depth.po.patch debian/patches/series
cp /toolkit/translations/kwin-wallpaper-cost.po.patch debian/patches/
echo kwin-wallpaper-cost.po.patch >> debian/patches/series
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d38.txt').read_text()
assert entry.startswith('kwin (4:6.7.4-2+stereo3d38) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# the source already asks for plasma-wayland-protocols +stereo3d10 and stops on a protocol without DisplayPort's flag
assert 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d10~)' in Path('debian/control').read_text()
assert 'stereo_sequential_displayport' in Path('debian/rules').read_text()
CHANGELOG
head -40 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s38/kwin_6.7.4-2+stereo3d38.dsc ../s38/kwin_6.7.4-2+stereo3d38.debian.tar.xz ../s38/kwin_6.7.4.orig.tar.xz ../s38/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d38.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d38+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
echo "== installing this round's builds first"
if ls /extra/*.deb >/dev/null 2>&1; then
    apt-get -y --no-install-recommends install /extra/*.deb > /work/extra-install.log 2>&1 || { tail -20 /work/extra-install.log; exit 1; }
fi
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the protocols the build uses: this round's (EXTRA_DIR) or the repository's
dpkg-query -W plasma-wayland-protocols
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
