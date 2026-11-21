#!/bin/bash
# Sparky Stereo OS: libxext 2:1.3.4-1+stereo3d1, Debian's 2:1.3.4-1 with the Generic Event extension's record kept for the
# life of the process (queue row 762c), built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor builds for the link gate, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
# libxext6-udeb (Debian-Installer's libXext, which the edition's installer, Calamares, does not use) is not built, as in the
# gtk4 and glib2.0 recipes: its udeb dependencies cannot be solved with the deb packages in one link-gate root. Debian's
# control has no profile for it, so the patch of Debian bug 1024924 (Helmut Grohne) adds <!noudeb> first.
# A UTF-8 locale, as Debian's build had: w3m writes libxext-doc's text pages by the locale, and in the image's POSIX locale
# every "©" became "?".
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck' DEB_BUILD_PROFILES=noudeb LC_ALL=C.UTF-8
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
for v in 2:1.3.4-1+b4 2:1.3.4-1; do
	dpkg --compare-versions 2:1.3.4-1+stereo3d1+lc1 gt "$v"
	echo "$(dpkg --print-architecture): 2:1.3.4-1+stereo3d1+lc1 > $v"
done
cd /work
mkdir s1 && cd s1
# Debian's 2:1.3.4-1 source package, format 1.0 (the .dsc pins the files)
echo '25024f57d955739c6b858822bf93ec3c71400b56fc0d666826f440e3661fd7c0  /src/libxext_1.3.4-1.dsc' | sha256sum -c
cp /src/libxext_1.3.4-1.dsc /src/libxext_1.3.4-1.diff.gz /src/libxext_1.3.4.orig.tar.gz .
dpkg-source -x libxext_1.3.4-1.dsc t >/dev/null
cd t
# Format 1.0 has no patch series: each patch is applied here, in this order, and kept with its header in debian/patches,
# so the new diff.gz carries both the change and its record.
mkdir debian/patches
for p in debian-bug-1024924-noudeb-profile.patch libxext-xge-static-extension-record.patch; do
	patch -p1 --forward --no-backup-if-mismatch < "/patches/$p"
	cp "/patches/$p" debian/patches/
done
grep -q '^Build-Profiles: <!noudeb>' debian/control
grep -q '^static XExtensionInfo xge_info_storage;' src/Xge.c
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('libxext (2:1.3.4-1+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('libxext (2:1.3.4-1) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -28 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
# the new source names Debian's orig tarball and a diff, never a native tarball
grep -q ' 8ef0789f282826661ff40a8eef22430378516ac580167da35cc948be9041aac1 494434 libxext_1.3.4.orig.tar.gz$' libxext_1.3.4-1+stereo3d1.dsc
grep -q ' libxext_1.3.4-1+stereo3d1.diff.gz$' libxext_1.3.4-1+stereo3d1.dsc
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/libxext_1.3.4-1+stereo3d1.dsc ../s1/libxext_1.3.4-1+stereo3d1.diff.gz ../s1/libxext_1.3.4.orig.tar.gz .
dpkg-source -x libxext_1.3.4-1+stereo3d1.dsc /work/lc/source >/dev/null
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 2:1.3.4-1+stereo3d1+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' gcc debhelper libx11-dev x11proto-dev pkgconf xutils-dev xmlto xsltproc w3m xorg-sgml-doctools >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
