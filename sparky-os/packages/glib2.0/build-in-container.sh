#!/bin/bash
# Sparky Stereo OS: glib2.0 2.90.1-2+stereo3d1, Debian's 2.90.1-2 with upstream's commit 4301b49671 (Thomas Hebb), built with
# Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor builds for the link gate, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
# libglib2.0-udeb (Debian-Installer's GLib, which the edition's installer, Calamares, does not use) is not built, as in the
# gtk4 recipe: its udeb dependencies cannot be solved with the deb packages in one link-gate root (libc6-udeb, libffi8-udeb)
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck' DEB_BUILD_PROFILES=noudeb
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 2.90.1-2 source package (the .dsc pins the files)
echo '899871dc1a0b96c0689d18cf87ceb096143e87da060c7ead318010566ce8f7fb  /src/glib2.0_2.90.1-2.dsc' | sha256sum -c
cp /src/glib2.0_2.90.1-2.dsc /src/glib2.0_2.90.1-2.debian.tar.xz /src/glib2.0_2.90.1.orig.tar.xz /src/glib2.0_2.90.1.orig-unicode-data.tar.xz .
dpkg-source -x glib2.0_2.90.1-2.dsc t >/dev/null
cd t
for p in /patches/gnetworkmonitornetlink-Avoid-deadlock-by-creating-enumerator-di.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('glib2.0 (2.90.1-2+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('glib2.0 (2.90.1-2) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -24 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/glib2.0_2.90.1-2+stereo3d1.dsc ../s1/glib2.0_2.90.1-2+stereo3d1.debian.tar.xz ../s1/glib2.0_2.90.1.orig.tar.xz ../s1/glib2.0_2.90.1.orig-unicode-data.tar.xz .
dpkg-source -x glib2.0_2.90.1-2+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 2.90.1-2+stereo3d1+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' gcc meson ninja-build python3 libffi-dev libpcre2-dev gobject-introspection gi-docgen >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
rm -rf /work/lc/source/debian/build 2>/dev/null || true
