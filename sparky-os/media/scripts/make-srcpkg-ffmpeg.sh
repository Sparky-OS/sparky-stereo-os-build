#!/bin/bash
# Source package of ffmpeg-dmo 10:9.0.2-dmo1+stereo3d2: dmo's own source package with our patches (unchanged since +stereo3d1),
# the changelog and, for the build without Fraunhofer's AAC, debian/rules and debian/control. Starts from the +stereo3d1 source
# package (dmo's source plus the nine patches), then lays the edited files of the build tree over its debian/.
set -eu
export HOME=/tmp/home; mkdir -p $HOME
# A source is dated by its own changelog entry, and its tree is normalized so the checkout time and the umask stay out (ORDER 421b)
REPRO=${REPRO:-/run/reproducible.py}
S=/w/srcpkg2
rm -rf $S; mkdir -p $S; cd $S
cp /w/src/ffmpeg-dmo_9.0.2.orig.tar.xz /w/src/ffmpeg-dmo_9.0.2.orig.tar.xz.asc .
cp /w/build-ff/ffmpeg-dmo_9.0.2-dmo1+stereo3d1.dsc /w/build-ff/ffmpeg-dmo_9.0.2-dmo1+stereo3d1.debian.tar.xz .
dpkg-source --no-check --no-preparation -x ffmpeg-dmo_9.0.2-dmo1+stereo3d1.dsc
cp /w/build-ff/ffmpeg-dmo-9.0.2/debian/rules /w/build-ff/ffmpeg-dmo-9.0.2/debian/control /w/build-ff/ffmpeg-dmo-9.0.2/debian/changelog ffmpeg-dmo-9.0.2/debian/
(cd ffmpeg-dmo-9.0.2 && dpkg-source --before-build .)
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" changelog ffmpeg-dmo-9.0.2/debian/changelog)}
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" ffmpeg-dmo-9.0.2
dpkg-source -b ffmpeg-dmo-9.0.2
(cd ffmpeg-dmo-9.0.2 && dpkg-source --after-build .)
rm -rf ffmpeg-dmo-9.0.2
rm -f ffmpeg-dmo_9.0.2-dmo1+stereo3d1.dsc ffmpeg-dmo_9.0.2-dmo1+stereo3d1.debian.tar.xz
ls -la
