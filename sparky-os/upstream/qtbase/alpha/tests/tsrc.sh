set -e
cd /work/tsrc-parent
tar xf /work/src/qt6-base_6.11.2+dfsg.orig.tar.xz
mv qtbase-everywhere-src-6.11.2 /work/tsrc
cd /work/tsrc
tar xf /work/src/qt6-base_6.11.2+dfsg-5+stereo3d2.debian.tar.xz
cp /work/src/qt6-base-6.11.2+dfsg/debian/patches/stereo3d-translucent-keeps-requested-depth.patch debian/patches/
grep -q translucent debian/patches/series || echo stereo3d-translucent-keeps-requested-depth.patch >> debian/patches/series
export QUILT_PATCHES=debian/patches
quilt push -a 2>&1 | tail -3
