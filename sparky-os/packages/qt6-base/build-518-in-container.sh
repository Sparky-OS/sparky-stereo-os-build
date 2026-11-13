#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
: "${SOURCE_DATE_EPOCH:?}" "${SOURCE_DATE_RFC2822:?}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
VERSION=6.11.2+dfsg-5+stereo3d17
BASE=6.11.2+dfsg-5+stereo3d15+lc1
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir plain lc
cp /repo/pool/main/q/qt6-base/qt6-base_"$BASE".dsc \
   /repo/pool/main/q/qt6-base/qt6-base_"$BASE".debian.tar.xz \
   /repo/pool/main/q/qt6-base/qt6-base_6.11.2+dfsg.orig.tar.xz plain/
cd plain
dpkg-source -x qt6-base_"$BASE".dsc source
python3 /toolkit/repo/plain-from-lc.py --save-plan /work/preserve.json source
cd source
for patch in /tools/patches/*.patch /tools/painting-patches/*.patch; do
    name=$(basename "$patch")
    grep -qxF "$name" debian/patches/series && continue
    cp "$patch" debian/patches/
    printf '%s\n' "$name" >> debian/patches/series
done
QUILT_PATCHES=debian/patches quilt push -a
# Quilt's text patches cannot carry git binary patches. Source format 3.0 carries
# these baked resources directly, with explicit inclusion and checked hashes.
(cd /tools/painting-shaders && sha256sum -c SHA256SUMS)
for shader in /tools/painting-shaders/*.qsb; do
    target=src/gui/painting/shaders/$(basename "$shader")
    cp "$shader" "$target"
    printf '%s\n' "$target" >> debian/source/include-binaries
done
python3 - <<'PY'
from pathlib import Path
import os
p=Path('debian/changelog')
entry='''qt6-base (6.11.2+dfsg-5+stereo3d17) unstable; urgency=medium

  * Paint Widgets on the selected GPU with either Qt's OpenGL engine or
    recorded batches; processor painting remains the default and all three
    ways remain available (ORDER 518).
  * Keep fractional element shifts and a decorated per-eye pair; report an
    unavailable GPU painting choice through the desktop's problems engine.
  * Carry ORDER 146b's existing stereo EGL configuration patch from this
    recipe. Version +stereo3d16 remains that order's reserved candidate.
  * Keep the header-sync ordering and public-header gate from +stereo3d15.

'''
p.write_text(entry+' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+os.environ['SOURCE_DATE_RFC2822']+'\n\n'+p.read_text())
# Terminology in the patch description, not in executable style identifiers.
for p in Path('debian/patches').glob('s8-0002*'):
    text=p.read_text();head,sep,body=text.partition('diff --git ')
    p.write_text(head.replace('Union on Stereo KWin','Stereo Union on Stereo KWin')+sep+body)
PY
python3 /toolkit/repo/provenance-files.py . 'o518-*.patch'
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b .
cd /work/lc
cp /work/plain/qt6-base_"$VERSION".dsc /work/plain/qt6-base_"$VERSION".debian.tar.xz \
   /work/plain/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_"$VERSION".dsc source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$VERSION+lc1" \
    --toolkit /toolkit --preserve-plan /work/preserve.json
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source > /work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" .
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/repo/pool/main/q/qt6-base \
    SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    DEBFULLNAME="$DEBFULLNAME" DEBEMAIL="$DEBEMAIL" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
