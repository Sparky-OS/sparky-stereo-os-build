#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 39: dolphin-emu 2609.b+dfsg-1+stereo3d1+lc1, inside the build container that build.sh starts.
# /work the job folder, /src Debian's source package, /prev Debian's own dolphin-emu build (the link gate's predecessor),
# /tools this folder, /toolkit the build tree's sparky-os, /repo the edition's published tree.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build.sh (sparky_provenance_init)}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
V=2609.b+dfsg-1 NEXT=2609.b+dfsg-1+stereo3d1
cd /work && mkdir s1 && cd s1
echo 'f814ca630589a07a3f6963d4c13475c9566fecbe8a77234c63798b9651239a24  /src/dolphin-emu_2609.b+dfsg-1.dsc' | sha256sum -c
cp /src/dolphin-emu_$V.dsc /src/dolphin-emu_$V.debian.tar.xz /src/dolphin-emu_2609.b+dfsg.orig.tar.xz .
dpkg-source -x dolphin-emu_$V.dsc t >/dev/null
cd t
for p in /tools/patches/stereo-1-one-declared-output.patch /tools/patches/stereo-2-translations.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
python3 /tools/overlay.py
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then dch --date "$DATE" -v "$NEXT" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
	n=$((n + 1))
done < /tools/changelog/dolphin-emu.items
head -12 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
mkdir -p /work/lc && cd /work/lc
cp ../s1/dolphin-emu_$NEXT.dsc ../s1/dolphin-emu_$NEXT.debian.tar.xz ../s1/dolphin-emu_2609.b+dfsg.orig.tar.xz .
dpkg-source -x dolphin-emu_$NEXT.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source $NEXT+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source > /work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' libstereo-declare-dev qt6-base-dev libsdl3-dev libvulkan-dev gcc > /work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
rm -rf /work/lc/source/build /work/lc/source/obj-* 2>/dev/null || true
ls -la /work/lc
