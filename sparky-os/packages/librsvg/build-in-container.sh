#!/bin/bash
# Sparky Stereo OS: librsvg 2.63.3+dfsg-1+stereo3d1, Debian's 2.63.3+dfsg-1 with the CSS colour patch, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor builds for the link gate, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 2.63.3+dfsg-1 source package (the .dsc pins the files)
echo '78bf6c29fb5402c3db536803524f78e6053697917a4d55352d7320af671697e9  /src/librsvg_2.63.3+dfsg-1.dsc' | sha256sum -c
cp /src/librsvg_2.63.3+dfsg-1.dsc /src/librsvg_2.63.3+dfsg-1.debian.tar.xz /src/librsvg_2.63.3+dfsg.orig.tar.xz .
dpkg-source -x librsvg_2.63.3+dfsg-1.dsc t >/dev/null
cd t
for p in /patches/stereo3d-css-colour-precision.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('librsvg (2.63.3+dfsg-1+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('librsvg (2.63.3+dfsg-1) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/librsvg_2.63.3+dfsg-1+stereo3d1.dsc ../s1/librsvg_2.63.3+dfsg-1+stereo3d1.debian.tar.xz ../s1/librsvg_2.63.3+dfsg.orig.tar.xz .
dpkg-source -x librsvg_2.63.3+dfsg-1+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
# No source needs keeping whole: the Rust sources and the test corpus (SVG, CSS, PNG) are no language Lean Code projects,
# and the vendored crates live in debian/, which it leaves alone.
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 2.63.3+dfsg-1+stereo3d1+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' rustc cargo libcairo2-dev >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
# the build tree goes once the packages are made: Cargo's targets fill disks
rm -rf /work/lc/source/target /work/lc/source/_build /work/lc/source/obj-* 2>/dev/null || true
