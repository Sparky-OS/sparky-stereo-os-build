# Sparky Stereo OS: kwin 4:6.7.4-2+stereo3d41, the +stereo3d40 source package plus patches/s41-* and the XREAL EDIDs, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, +stereo3d36 2026/10/29, +stereo3d37 to +stereo3d39 2026/10/30, +stereo3d40 2026/10/31,
# +stereo3d41 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d40 source package,
# /extra the builds the repository does not have yet (nothing for +stereo3d41), /prev the earlier +lc1 builds,
# /patches this folder's patches, /toolkit the build tree's sparky-os folder.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s41 && cd s41
# the plain +stereo3d40 source package, plain-from-lc.py's from the published +stereo3d40+lc1 source (ORDER 330,
# source-plain-40; its contents equal ORDER 319's source-plain); its .dsc pins the files
echo 'a018555e391b795e5ceb16f500c61f984118d94957ea7ea296c2fbdb65a2a793  /src/kwin_6.7.4-2+stereo3d40.dsc' | sha256sum -c
cp /src/kwin_6.7.4-2+stereo3d40.dsc /src/kwin_6.7.4-2+stereo3d40.debian.tar.xz /src/kwin_6.7.4.orig.tar.xz /src/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d40.dsc t >/dev/null
cd t
# the translations stay as +stereo3d38 carries them (kwin-wallpaper-cost.po.patch before the s39 patches); the s41 patch
# adds no strings
grep -qx kwin-wallpaper-cost.po.patch debian/patches/series
grep -qx s40-0001-scene-Draw-the-background-below-blending-windows-in-.patch debian/patches/series
for p in /patches/s41-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
# the XREAL One Pro EDIDs testMockDrmGlasses reads (ORDER 322): s34-0010 adds them, but a quilt patch carries no binary
# file, so each is made from the hex dump s34-0010 carries beside it, checked against the Sparky-OS/kwin blob, and kept in
# the debian tarball, which "can also contain binary files outside of that directory" listed in
# debian/source/include-binaries (dpkg-source(1))
python3 - <<'EDIDS'
import hashlib
from pathlib import Path
blobs = {
    'xreal-one-pro-2d': 'c2c796bf64af36aa90112ee048c85674e892c5c31d4ca6a66be31e4324a5ba05',
    'xreal-one-pro-full': '970ac1be98afc5086711e913e4e6be48b0b9d7e02f6e951980f0f89c1bb4e636',
    'xreal-one-pro-half': 'c2c796bf64af36aa90112ee048c85674e892c5c31d4ca6a66be31e4324a5ba05',
    'xreal-one-pro-realD': '93dcc33e5338d8a35a1b891e56baa86434c79e8326a5ea808a38383f731f6287',
}
data = Path('autotests/integration/data')
listing = Path('debian/source/include-binaries')
assert not listing.exists()
names = []
for name, sha in blobs.items():
    dump = (data / f'{name}.txt').read_text().split('edid-decode (hex):', 1)[1].split('----------------', 1)[0]
    edid = bytes.fromhex(''.join(dump.split()))
    assert len(edid) == 128 and hashlib.sha256(edid).hexdigest() == sha, name
    assert not (data / f'{name}.bin').exists(), name
    (data / f'{name}.bin').write_bytes(edid)
    names.append(f'{data}/{name}.bin')
listing.write_text(''.join(n + '\n' for n in names))
EDIDS
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d41.txt').read_text()
assert entry.startswith('kwin (4:6.7.4-2+stereo3d41) unstable;'), entry[:60]
assert p.read_text().startswith('kwin (4:6.7.4-2+stereo3d40) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# the source already asks for plasma-wayland-protocols +stereo3d10 and stops on a protocol without DisplayPort's flag
assert 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d10~)' in Path('debian/control').read_text()
assert 'stereo_sequential_displayport' in Path('debian/rules').read_text()
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s41/kwin_6.7.4-2+stereo3d41.dsc ../s41/kwin_6.7.4-2+stereo3d41.debian.tar.xz ../s41/kwin_6.7.4.orig.tar.xz ../s41/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d41.dsc /work/lc/source >/dev/null
# the EDIDs came back from the debian tarball
(cd /work/lc/source && sha256sum autotests/integration/data/xreal-one-pro-*.bin)
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d41+lc1 --toolkit /toolkit
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
